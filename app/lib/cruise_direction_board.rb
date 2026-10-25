# frozen_string_literal: true

# The Cruise Direction page's data layer: a year's dirt shifts for the picker,
# one shift's pods for the board, and the candidates the add dialog offers.
#
# Upstream spreads this across the Ember route and three API endpoints the page
# calls separately (slot/dirt-shift-times, position, timesheet), stitching the
# results together in the browser. All of it lands here so the board renders
# from one shape and a mutation can stream the whole thing back.
#
# The Alpha Pod Management page has its own board object. The two look alike
# and stay apart on purpose: an Alpha pod is a trio of rows with an eligibility
# rule per kind of member, and a shift pod is one row whose members are simply
# whoever is on duty in a Cruise Direction position.
class CruiseDirectionBoard
  # The shifts this page runs against, matching Slot.retrieve_dirt_times.
  DIRT_POSITIONS = [Position::DIRT, Position::DIRT_PRE_EVENT, Position::DIRT_POST_EVENT].freeze

  # Checked in this long before the shift start or earlier, and they are
  # probably still out on the shift before this one. Upstream splits the add
  # dialog on exactly this and folds the earlier list away.
  PRIOR_SHIFT_CUTOFF = 1.hour

  # One person in one pod. `on_duty_at` and `position_title` come from their
  # open timesheet; both are nil for someone whose shift has ended, which is
  # what the card reads back as "not checked in". They stay in the pod either
  # way -- only a removal ends a membership.
  Member = Data.define(:person, :on_duty_at, :position_title) do
    def on_duty? = !on_duty_at.nil?
  end

  # One pod as the card renders it.
  PodCard = Data.define(:pod, :members) do
    def location = pod.location
    def transport = pod.transport
    def empty? = members.empty?
    def disbanded? = pod.disbanded?
  end

  # One shift's pods, plus the number this page exists to drive down: people on
  # duty for the shift that no one has put in a pod.
  Board = Data.define(:slot, :cards, :unassigned) do
    def any? = cards.any?
    def pod_count = cards.size
    def member_count = cards.sum { |card| card.members.size }
    def unassigned_count = unassigned.size
  end

  # Someone the add dialog can offer: on duty in a Cruise Direction position
  # and in no pod on this shift.
  Candidate = Data.define(:person, :on_duty_at, :position_title)

  # The dialog's two lists. `current` is nearly always the right answer; the
  # people who look like they are still on the previous shift are folded away.
  Pools = Data.define(:current, :prior) do
    def any? = current.any? || prior.any?
  end

  class << self
    # The year's dirt shifts, oldest first, for the shift picker.
    def shifts_for_year(year) = Slot.retrieve_dirt_times(year)

    # The shift the page opens on: the last one that has started and not yet
    # ended. nil outside the event, when nothing is running and the reader has
    # to pick a shift themselves.
    def suggested_shift(shifts) = shifts.reverse.find { |shift| shift.has_started && !shift.has_ended }

    # One shift's pods with their members.
    def for_slot(slot)
      pods = Pod.shift_pods_for(slot).to_a
      members = members_by_pod(pods.map(&:id), slot)
      cards = pods.map { |pod| PodCard.new(pod:, members: members[pod.id] || []) }

      Board.new(slot:, cards:, unassigned: available_candidates(slot))
    end

    # The add dialog's candidates, split at the prior-shift cutoff. Loaded when
    # the dialog opens rather than with the page.
    def pools_for(slot) = pools_from(available_candidates(slot), slot)

    # The same split, over candidates already in hand -- the board carries them
    # as `unassigned`, and creating a pod opens the add dialog on the spot.
    def pools_from(candidates, slot)
      prior, current = candidates.partition { |candidate| prior_shift?(candidate, slot) }

      Pools.new(current:, prior:)
    end

    # The positions someone must be signed in to to appear on this page. Held
    # by a checkbox on the position record, so operators can change the list
    # without a deploy -- which is also why the page can show it on request.
    #
    # The query is one positional hash: find_for_query's second argument is a
    # keyword, so passing these loose makes Ruby read them as keywords too and
    # the call raises rather than filtering.
    def positions = Position.find_for_query({ cruise_direction: true, active: true })

    # Everyone whose open shift overlaps this one in a Cruise Direction
    # position, whether or not they are already in a pod.
    #
    # This is what a submitted id is checked against, and it deliberately does
    # NOT subtract the people already podded: being in another pod is a
    # different refusal with a better message, and Pod#add_person! is what
    # says it.
    def eligible_person_ids(slot) = on_duty_rows(slot).map(&:person_id).to_set

    private

    # Every current membership of the given pods, in callsign order, with the
    # open-timesheet details the card shows. Four queries for the whole board
    # rather than a pair per pod.
    def members_by_pod(pod_ids, slot)
      return {} if pod_ids.empty?

      # PersonPod.ordered joins :person, so a membership whose person is gone
      # -- person_pod carries no foreign key, and Laravel writes the table too
      # -- drops out here while still counting toward pod.person_count.
      rows = PersonPod.current.where(pod_id: pod_ids).ordered
                      .includes(person: :avatar_photo_attachment).to_a
      return {} if rows.empty?

      duty = on_duty_by_person(rows.map(&:person_id).uniq, slot)

      rows.group_by(&:pod_id).transform_values do |pod_rows|
        pod_rows.map do |row|
          on_duty_at, position_title = duty[row.person_id]
          Member.new(person: row.person, on_duty_at:, position_title:)
        end
      end
    end

    # Whichever shift each of these people is on that overlaps THIS one.
    #
    # Ordered so that someone holding more than one open entry -- which is a
    # data fault, but a reachable one -- is reported by their latest, not by
    # whichever row the database happened to return last into the hash.
    def on_duty_by_person(person_ids, slot)
      covering(slot).where(person_id: person_ids)
                    .order(:on_duty)
                    .includes(:position)
                    .to_h { |entry| [entry.person_id, [entry.on_duty, entry.position&.title]] }
    end

    # Open timesheets that genuinely covered this shift.
    #
    # Both bounds earn their place. Without the upper one, an open entry means
    # "on duty right now", so last Tuesday's card reads back tonight's position
    # and check-in time -- and the year selector and shift picker both invite
    # looking at a shift that is not the one running.
    #
    # Without the lower one, a never-closed entry from earlier in the same
    # event matches every later shift for the rest of the year. Those exist --
    # closing them is what the Mass Sign-Out page is for -- and `sign_in`
    # answers `:already_on_duty` for such a person, so they never get a fresher
    # entry to be found by. They would sit in "Waiting for a pod" permanently,
    # inflating the one number this page exists to drive to zero, with no
    # control here able to clear them.
    #
    # A shift-length of slack before the start is what the previous shift's
    # crew need: still being out on the shift before is ordinary, and the add
    # dialog folds exactly those people away under PRIOR_SHIFT_CUTOFF.
    def covering(slot)
      Timesheet.for_year(slot.begins_year)
               .where(on_duty: (slot.begins - (slot.ends - slot.begins))..slot.ends)
               .on_duty_now
    end

    # People on duty in a Cruise Direction position with no pod on this shift.
    # Both the add dialog's source and the board's "no one has picked them up
    # yet" count -- one rule, so the dialog can never offer someone the count
    # has already forgotten about.
    def available_candidates(slot)
      rows = on_duty_rows(slot)
      return [] if rows.empty?

      podded = podded_person_ids(slot)

      rows.reject { |row| row.person.nil? || podded.include?(row.person_id) }
          .sort_by { |row| row.person.callsign.to_s.downcase }
          .map do |row|
            Candidate.new(person: row.person, on_duty_at: row.on_duty, position_title: row.position&.title)
          end
    end

    # Open shifts in a Cruise Direction position that covered this one, newest
    # first per person so `uniq` keeps the entry that best describes them.
    def on_duty_rows(slot)
      position_ids = positions.map(&:id)
      return [] if position_ids.empty?

      covering(slot).where(position_id: position_ids)
                    .order(on_duty: :desc)
                    .includes(:person, :position)
                    .to_a
                    .uniq(&:person_id)
    end

    def podded_person_ids(slot)
      PersonPod.current
               .where(pod_id: Pod.for_slot(slot).of_type(Pod::TYPE_SHIFT).select(:id))
               .pluck(:person_id).to_set
    end

    # Upstream compares whole hours, so exactly an hour early counts as the
    # previous shift.
    def prior_shift?(candidate, slot)
      candidate.on_duty_at.present? && candidate.on_duty_at <= slot.begins - PRIOR_SHIFT_CUTOFF
    end
  end
end
