# frozen_string_literal: true

# The Alpha Pod Management page's data layer: a year's Alpha shifts for the
# index, one shift's pods for the editor, and the candidate pools the add
# dialog offers.
#
# Upstream spreads this across the Ember route (which stitches the trios
# together client-side) and four separate API endpoints the add dialog calls
# on open. Both jobs land here so the page and the print sheet read one shape.
#
# Three of upstream's eligibility rules are corrected rather than copied --
# see NOT_CHECKED_IN below and the plan's issues table.
class AlphaPodBoard
  # How far either side of the shift start a check-in still counts as being
  # for this walk. Upstream's dialog legend claims -1/+2 hours for Alphas, but
  # its code computes plus-or-minus one hour for everyone; the code is what
  # mentors have been using, so the window stays and the wording matches it.
  CHECK_IN_WINDOW = 1.hour

  # Which positions someone must be signed in to to count as available for
  # each kind of pod. The mentor cadre spreads across the whole family --
  # a Khaki or a Cheetah on duty is still a mentor who can take a pod.
  ON_DUTY_POSITIONS = {
    Pod::TYPE_MENTOR => [
      Position::MENTOR, Position::MENTOR_LEAD, Position::MENTOR_SHORT,
      Position::MENTOR_RADIO_TRAINER, Position::MENTOR_KHAKI,
      Position::MENTOR_WHEEL_OF_MANY_WAYS, Position::CHEETAH
    ].freeze,
    Pod::TYPE_MITTEN => [Position::MENTOR_MITTEN, Position::MENTOR_APPRENTICE].freeze,
    Pod::TYPE_ALPHA => [Position::ALPHA].freeze
  }.freeze

  # Who the "not checked in" list falls back to for each pod type. Mentors and
  # MITtens are found by the position they hold; Alphas by their status.
  #
  # All three corrected from upstream, which (a) excluded any Alpha who had
  # ever held a timesheet in any year rather than one who is on duty now --
  # a left join with a whereNull that reads as a bug, not a rule -- and (b)
  # cross-checked the mentor list against the on-duty list but not the MITten
  # list, so a signed-in MITten appeared in both pools at once.
  GRANTED_POSITIONS = {
    Pod::TYPE_MENTOR => Position::MENTOR,
    Pod::TYPE_MITTEN => Position::MENTOR_MITTEN
  }.freeze

  GROUP_TITLES = {
    Pod::TYPE_MENTOR => "Mentors",
    Pod::TYPE_MITTEN => "MITtens",
    Pod::TYPE_ALPHA => "Alphas"
  }.freeze

  # One person in one pod. `bonk_years` is the whole career, matching
  # upstream's prior_bonk flag, which is not year-scoped either -- a mentor
  # wants to know someone has bonked before whatever year it happened. Only
  # the Alpha lists surface it: on a mentor or a MITten it is their own
  # history and not something the pod they are running needs to announce.
  Member = Data.define(:person, :is_lead, :on_duty, :bonk_years) do
    def lead? = is_lead
    def on_duty? = on_duty
    def prior_bonk? = bonk_years.any?
  end

  # One sub-pod of a trio: the row people are actually added to.
  Group = Data.define(:pod, :type, :title, :members)

  # A trio, as the card renders it. The number is the mentor pod's, which is
  # the only number anyone says out loud.
  PodSet = Data.define(:mentor_pod, :groups) do
    def number = mentor_pod.sort_index
    def group(type) = groups.find { |group| group.type == type }
    def member_count = groups.sum { |group| group.members.size }
    def empty? = member_count.zero?
  end

  # One shift's pods, plus the number the page exists to drive down: Alphas
  # who are signed in and still standing at check-in with no pod.
  Board = Data.define(:slot, :sets, :unassigned_alphas) do
    def any? = sets.any?
    def count_of(type) = sets.sum { |set| set.group(type)&.members&.size.to_i }
    def unassigned_count = unassigned_alphas.size
  end

  # Someone the add dialog can offer. `pod_number` is set when they are
  # already in a pod of this type on this shift, which disables the row --
  # the same guard Pod#add_person! enforces server-side.
  Candidate = Data.define(:person, :on_duty_at, :position_title, :pod_number) do
    def assigned? = !pod_number.nil?
  end

  # The dialog's three lists. `near` is the one that is nearly always the
  # right answer; the other two are collapsed behind a disclosure.
  Pools = Data.define(:near, :other, :not_checked_in) do
    def any? = near.any? || other.any? || not_checked_in.any?
  end

  class << self
    # The year's Alpha shifts with a pod count each, for the index cards.
    #
    # Active only, unlike the Alpha Schedule which badges inactive shifts:
    # pods are formed on the day from people signed in to a running shift, so
    # a dormant slot has nothing to manage. Upstream's page says as much
    # ("Only activated shifts are shown") while sending no such filter.
    def shifts_for_year(year)
      shifts = AlphaShiftRoster.shifts_for_year(year).select { |shift| shift.slot.active }
      return [[], {}] if shifts.empty?

      pod_counts = Pod.where(slot_id: shifts.map { |shift| shift.slot.id }, type: Pod::TYPE_MENTOR)
                      .group(:slot_id).count

      [shifts, pod_counts]
    end

    # One shift's pods, stitched into trios and ordered by pod number.
    def for_slot(slot)
      mentor_pods = Pod.mentor_pods_for(slot).to_a
      sub_pods = Pod.for_slot(slot).where(mentor_pod_id: mentor_pods.map(&:id)).group_by(&:mentor_pod_id)

      members = members_by_pod(mentor_pods.map(&:id) + sub_pods.values.flatten.map(&:id))

      sets = mentor_pods.map do |mentor_pod|
        pods = { Pod::TYPE_MENTOR => mentor_pod }
        (sub_pods[mentor_pod.id] || []).each { |pod| pods[pod.type] = pod }

        groups = Pod::ALPHA_SET_TYPES.filter_map do |type|
          pod = pods[type]
          Group.new(pod:, type:, title: GROUP_TITLES[type], members: members[pod.id] || []) if pod
        end

        PodSet.new(mentor_pod:, groups:)
      end

      Board.new(slot:, sets:, unassigned_alphas: unassigned_alphas(slot, sets))
    end

    # The three candidate lists for one sub-pod's add dialog. Loaded when the
    # dialog opens rather than with the page -- four queries no one pays for
    # until they press Add.
    def pools_for(pod, slot)
      on_duty = on_duty_candidates(pod, slot)
      near, other = on_duty.partition { |candidate| within_window?(candidate.on_duty_at, slot) }

      Pools.new(near:, other:, not_checked_in: not_checked_in_candidates(pod, slot, on_duty))
    end

    private

    # Every current membership of the given pods, in display order, with the
    # bonk history and on-duty state the chips show. Two queries for the whole
    # board rather than two per pod.
    def members_by_pod(pod_ids)
      return {} if pod_ids.empty?

      rows = PersonPod.current.where(pod_id: pod_ids).ordered.includes(:person).to_a
      return {} if rows.empty?

      person_ids = rows.map(&:person_id).uniq
      bonks = PersonMentor.bonk_years_by_person(person_ids, position_id: Position::ALPHA)
      on_duty = Timesheet.where(person_id: person_ids).on_duty_now.pluck(:person_id).to_set

      rows.group_by(&:pod_id).transform_values do |pod_rows|
        pod_rows.map do |row|
          Member.new(person: row.person, is_lead: row.is_lead,
                     on_duty: on_duty.include?(row.person_id),
                     bonk_years: bonks[row.person_id] || [])
        end
      end
    end

    # Alphas signed in to this shift's position who are in no pod yet. The
    # count this page exists to drive to zero: someone standing at check-in
    # that no one has picked up.
    def unassigned_alphas(slot, sets)
      signed_in = Timesheet.retrieve_signed_in_people(Position::ALPHA)
      return [] if signed_in.empty?

      podded = sets.flat_map { |set| set.group(Pod::TYPE_ALPHA)&.members || [] }
                   .map { |member| member.person.id }.to_set

      Person.where(id: signed_in.keys - podded.to_a)
            .order(:callsign).to_a
    end

    # People on an open timesheet in a position that qualifies them for this
    # kind of pod, tagged with the pod they are already in, if any.
    def on_duty_candidates(pod, slot)
      rows = Timesheet.where(position_id: ON_DUTY_POSITIONS[pod.type])
                      .for_year(slot.begins_year)
                      .on_duty_now
                      .includes(:person, :position)
                      .to_a

      build_candidates(rows.map(&:person), pod, slot,
                       on_duty_at: rows.to_h { |row| [row.person_id, row.on_duty] },
                       titles: rows.to_h { |row| [row.person_id, row.position&.title] })
    end

    # The fallback list: qualified people with no open timesheet at all.
    # Excluding everyone already offered above is what makes the three lists
    # a partition instead of three overlapping guesses.
    def not_checked_in_candidates(pod, slot, on_duty)
      offered = on_duty.map { |candidate| candidate.person.id }

      people =
        if (position_id = GRANTED_POSITIONS[pod.type])
          Person.joins(:person_position).where(person_position: { position_id: })
        else
          Person.where(status: Person::ALPHA)
        end

      build_candidates(people.where.not(id: offered).to_a, pod, slot)
    end

    def build_candidates(people, pod, slot, on_duty_at: {}, titles: {})
      numbers = pod_numbers_by_person(pod, slot)

      people.uniq.sort_by { |person| person.callsign.to_s.downcase }.map do |person|
        Candidate.new(person:,
                      on_duty_at: on_duty_at[person.id],
                      position_title: titles[person.id],
                      pod_number: numbers[person.id])
      end
    end

    # Which pod number, if any, each person already sits in for this type of
    # pod on this shift.
    def pod_numbers_by_person(pod, slot)
      pods = Pod.for_slot(slot).of_type(pod.type).includes(:mentor_pod).to_a
      return {} if pods.empty?

      by_id = pods.index_by(&:id)

      PersonPod.current.where(pod_id: pods.map(&:id))
               .pluck(:person_id, :pod_id)
               .to_h { |person_id, pod_id| [person_id, by_id[pod_id]&.number] }
    end

    def within_window?(on_duty_at, slot)
      return false if on_duty_at.blank?

      (slot.begins - CHECK_IN_WINDOW..slot.begins + CHECK_IN_WINDOW).cover?(on_duty_at)
    end
  end
end
