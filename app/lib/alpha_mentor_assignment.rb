# frozen_string_literal: true

# The Alpha Mentor Assignments worksheet: which mentors walked with each Alpha,
# and how the walk ended. Upstream Ember mentor/assignment, backed by
# MentorController::{alphas,mentors,mentorAssignment} and app/Lib/Alpha.php's
# retrieveAllAlphas / retrieveMentors / mentorAssignments / syncMentors.
#
# The roster is a CURRENT-STANDING snapshot -- everyone whose status is Alpha
# right now, exactly as upstream's mentor/alphas reads it. The year scopes only
# the shift sign-ups, the check-in state, and which mentor rows are being
# edited; it never selects the people.
#
# Recording a pass or a bonk here does NOT change anyone's account status. That
# is the Convert Alphas page's job, and the page copy says so.
class AlphaMentorAssignment
  # Upstream's MENTOR_COUNT: three mentor slots per Alpha, so three selects per
  # row. Nothing in the schema enforces three -- see Entry#overflow_mentors for
  # what happens to a fourth.
  MENTOR_SLOTS = 3

  # Filter sentinels. They live here rather than on the controller because a
  # helper that names a controller constant at load time deadlocks the two
  # autoloads against each other (the lesson from the Acceptance Sheets port).
  ALL_FILTER = "all"

  STATUS_PENDING_WITH_MENTORS = "pending"
  STATUS_PASSED = "passed"
  STATUS_BONKED = "bonked"

  SHIFT_NOT_CHECKED_IN = "not-checked-in"
  SHIFT_CHECKED_IN = "checked-in"
  # A shift-specific filter value is the sentinel, a dash, and a slot id --
  # "checked-in-30586" / "signed-up-30586". Upstream keys these off the raw
  # MySQL datetime string of slot.begins; a slot id survives the round trip
  # through a query string without any date parsing on either end.
  CHECKED_IN_PREFIX = "checked-in-"
  SIGNED_UP_PREFIX = "signed-up-"

  # One mentor the selects can offer. `on_duty` is upstream's `working` flag --
  # an open timesheet on the Mentor position this year. Never surfaced with
  # that name: "work" is banned UI vocabulary.
  Mentor = Data.define(:id, :callsign, :on_duty) do
    def on_duty? = on_duty
  end

  # One Alpha's row on the worksheet.
  #
  # `mentors` is every stored mentor for the year, callsign-sorted, as
  # `{ id:, callsign: }`. `status` is the year's verdict, defaulting to pending
  # when no row exists: an Alpha no one has recorded yet and one recorded as
  # still walking are both pending, so the filters compare this derived value
  # rather than querying the column.
  #
  # `shift_slot` is the Alpha shift the person is currently signed in to, and is
  # nil both when they are not checked in and when the open timesheet cannot be
  # tied to one of this year's Alpha shifts (upstream's "walking unknown").
  Entry = Data.define(:person, :alpha_slots, :checked_in, :shift_slot, :mentors,
                      :status, :prior_years) do
    def checked_in? = checked_in

    # Checked in, but no one can tell which walk -- a very early or very late
    # check-in, or a sign-in with no shift attached. Upstream warns about these
    # because the pod fill cannot place them either.
    def walking_unknown? = checked_in && shift_slot.nil?

    def mentor_ids = mentors.map { |mentor| mentor[:id] }

    # A year is allowed more than three mentor rows -- the unique index is on
    # (person, mentor, year, position), not on a count. Upstream pads to three and hides
    # the rest, then quietly deletes them on the next save. Here they are named
    # on the row instead, so nothing disappears without being read first.
    def overflow_mentors = mentors.drop(MENTOR_SLOTS)
    def overflow? = mentors.size > MENTOR_SLOTS

    def pending? = status == PersonMentor::STATUS_PENDING
    def passed? = status == PersonMentor::STATUS_PASS
    def bonked? = [PersonMentor::STATUS_BONK, PersonMentor::STATUS_SELF_BONK].include?(status)
  end

  # What one submitted row asks for, after the wire format has been unpacked.
  # `mentors_malformed` marks a mentor list that was missing or held something
  # other than ids.
  # The list replaces what is stored, so it is refused rather than read as fewer
  # mentors -- which would remove the rest.
  Row = Data.define(:person_id, :status, :mentor_ids, :mentors_malformed) do
    def initialize(person_id:, status:, mentor_ids:, mentors_malformed: false) = super
  end

  # The outcome of a save. `row_errors` is keyed by person id, so the view can
  # tint exactly the rows that need fixing; anything in it means nothing at all
  # was written.
  Result = Data.define(:row_errors, :saved_count, :cleared_count) do
    def ok? = row_errors.empty?
    def changed_count = saved_count + cleared_count
  end

  # What a pod fill did, so the page can say who it touched and who it could
  # not. Upstream promises this report in its markup and then never fills it in.
  #
  # `not_assignable` are pod mentors this page cannot record: a pod is formed
  # from the whole mentor cadre (Khaki, Cheetah, Lead and the rest), while an
  # assignment may only name a Mentor-position holder. They are reported rather
  # than copied, because a copied id has no option to render and would vanish
  # from the row without a word.
  #
  # `pod_count` lets the page tell "that shift has no pods yet" apart from
  # "the pods are all already recorded", which otherwise look identical.
  PrefillResult = Data.define(:rows, :filled, :skipped, :not_listed, :not_assignable, :pod_count) do
    def pods? = pod_count.positive?
  end

  class << self
    # Every current Alpha, callsign-sorted, carrying the worksheet's columns.
    # Every source is bulk-loaded, so the query count is flat in roster size.
    #
    # @param year [Integer] scopes shift sign-ups, check-in state, and the
    #   mentor rows being edited
    # @return [Array<Entry>]
    def roster(year)
      people = Person.where(status: Person::ALPHA)
                     .to_a
                     .sort_by { |person| person.callsign.to_s.downcase }
      return [] if people.empty?

      person_ids = people.map(&:id)
      slots_by_person = alpha_slots_by_person(person_ids, year)
      mentorships = PersonMentor.retrieve_all_mentors_for_ids(person_ids, position_id: Position::ALPHA)
      signed_in = signed_in_alphas(year)
      slots_by_id = alpha_slots_for_year(year).index_by(&:id)

      people.map do |person|
        build_entry(person, year, slots_by_person, mentorships, signed_in, slots_by_id)
      end
    end

    # The mentors the selects offer: everyone holding the Mentor position,
    # callsign-sorted, flagged with whether they are signed in right now.
    #
    # Deliberately NOT the wider mentor cadre the pod board draws on (Khaki,
    # Cheetah, and friends): upstream's assignment pool is strictly position 9,
    # and the pool is also what the save validates against.
    def mentor_pool(year)
      people = Person.joins(:person_position)
                     .where(person_position: { position_id: Position::MENTOR })
                     .select(:id, :callsign)
                     .to_a
                     .uniq(&:id)
      return [] if people.empty?

      on_duty = Timesheet.where(person_id: people.map(&:id), position_id: Position::MENTOR)
                         .for_year(year)
                         .on_duty_now
                         .pluck(:person_id)
                         .to_set

      people.sort_by { |person| person.callsign.to_s.downcase }
            .map { |person| Mentor.new(id: person.id, callsign: person.callsign, on_duty: on_duty.include?(person.id)) }
    end

    # Mentors already recorded on the roster who have since lost the Mentor
    # position. Without them the select would render blank for a real stored
    # assignment and the next save would silently drop it. Rare but real: one of
    # the 45 mentors used in the 2025 season no longer holds the position.
    def former_mentors(entries, pool)
      known = pool.map(&:id).to_set
      ids = entries.flat_map(&:mentor_ids).uniq.reject { |id| known.include?(id) }
      return [] if ids.empty?

      Person.where(id: ids)
            .select(:id, :callsign)
            .to_a
            .sort_by { |person| person.callsign.to_s.downcase }
            .map { |person| Mentor.new(id: person.id, callsign: person.callsign, on_duty: false) }
    end

    # This year's Alpha shifts, earliest first. Inactive shifts are listed for
    # the same reason the Acceptance Sheets list them: a dormant shift that
    # still has sign-ups is exactly what wants noticing.
    def alpha_slots_for_year(year)
      Slot.for_year(year).for_position(Position::ALPHA).ordered_by_begins.to_a
    end

    # Upstream's "No Bonks?" prompt, reproduced rule for rule: it fires when at
    # least one Alpha is being passed and none is being bonked. Both counts
    # ignore rows with no mentors (upstream never submits those), and
    # self-bonks deliberately do NOT count as bonks -- a sheet of passes plus
    # self-bonks still asks.
    #
    # Never asked of a sheet with a malformed mentor list: assign! refuses it,
    # while the question's redraw would show the row as only the ids it kept.
    def needs_bonk_confirmation?(rows)
      return false if rows.any?(&:mentors_malformed)

      scoreable = rows.select { |row| row.mentor_ids.any? }
      passed = scoreable.count { |row| row.status == PersonMentor::STATUS_PASS }
      bonked = scoreable.count { |row| row.status == PersonMentor::STATUS_BONK }

      passed.positive? && bonked.zero?
    end

    # Record the sheet.
    #
    # Every row is validated first and the whole batch is written in ONE
    # transaction -- upstream gives each Alpha its own, so an interruption
    # leaves half a sheet recorded. Any row error means nothing is written.
    #
    # @param year [Integer]
    # @param rows [Array<Row>]
    # @return [Result]
    def assign!(year, rows)
      people = Person.where(status: Person::ALPHA, id: rows.map(&:person_id)).index_by(&:id)
      # Rows for anyone who is not a current Alpha simply drop out, which is
      # what keeps a hand-edited form to the page's own roster.
      rows = rows.select { |row| people.key?(row.person_id) }

      # Alpha rows only: sync_row destroys every stored row not on the sheet, so
      # another position's walk for the same person and year must stay out of
      # `existing`.
      existing = PersonMentor.where(person_id: rows.map(&:person_id), mentor_year: year, position_id: Position::ALPHA)
                             .group_by(&:person_id)
      row_errors = validate(rows, existing)
      return Result.new(row_errors:, saved_count: 0, cleared_count: 0) if row_errors.any?

      saved = 0
      cleared = 0

      PersonMentor.transaction do
        rows.each do |row|
          stored = existing[row.person_id] || []
          next unless sync_row(row, year, stored)

          row.mentor_ids.empty? ? cleared += 1 : saved += 1
        end
      end

      Result.new(row_errors: {}, saved_count: saved, cleared_count: cleared)
    end

    # Copy each pod's mentors onto the Alphas walking with them.
    #
    # Only BLANK mentor slots are filled. Upstream's markup promises exactly
    # this ("not updated because they already have mentor assignments") while
    # its code overwrites every slot unconditionally and never populates the
    # list it renders; the promise is what ships here.
    #
    # Nothing is written -- the caller re-renders the worksheet with the filled
    # values so a person can look before saving.
    #
    # @param slot [Slot] the Alpha shift whose pods to read
    # @param rows [Hash{Integer => Row}] the worksheet as currently submitted
    # @return [PrefillResult]
    def pod_prefill(slot, rows)
      pods = Pod.for_slot(slot).where(type: [Pod::TYPE_MENTOR, Pod::TYPE_ALPHA]).to_a
      mentors_by_alpha, not_assignable = pod_mentor_ids_by_alpha(pods)
      filled = []
      skipped = []
      not_listed = []

      mentors_by_alpha.each do |person_id, mentor_ids|
        row = rows[person_id]
        # In a pod, but not a row on this page -- filtered out, or no longer an
        # Alpha. Upstream conflates those two into one message; naming the
        # people lets the reader tell which it is.
        next not_listed << person_id if row.nil?
        next skipped << person_id if row.mentor_ids.any?

        rows[person_id] = Row.new(person_id:, status: row.status, mentor_ids: mentor_ids.first(MENTOR_SLOTS))
        filled << person_id
      end

      PrefillResult.new(rows:, filled: callsigns_for(filled), skipped: callsigns_for(skipped),
                        not_listed: callsigns_for(not_listed),
                        not_assignable: callsigns_for(not_assignable),
                        pod_count: pods.count(&:mentor?))
    end

    private

    def build_entry(person, year, slots_by_person, mentorships, signed_in, slots_by_id)
      history = mentorships[person.id] || {}
      current = history[year]
      timesheet = signed_in[person.id]

      Entry.new(
        person:,
        alpha_slots: slots_by_person[person.id] || [],
        checked_in: !timesheet.nil?,
        # Only a slot from this year's Alpha shifts counts. A timesheet with no
        # slot, or one pointing at some other shift, leaves this nil and the
        # row lands in the "cannot tell which walk" warning.
        shift_slot: timesheet && slots_by_id[timesheet.slot_id],
        mentors: current ? current[:mentors] : [],
        status: current ? current[:status] : PersonMentor::STATUS_PENDING,
        # Upstream drops the current year from the prior list in the browser;
        # the data layer will not do it for you. Newest year first, the way
        # every other mentor-history readout in this app orders it.
        prior_years: PersonMentor.history_rows(history.except(year)).reverse
      )
    end

    # This year's Alpha sign-ups per person, earliest first. Same query the
    # Acceptance Sheets use, inactive shifts included.
    def alpha_slots_by_person(person_ids, year)
      PersonSlot.eager_load(:slot)
                .where(person_id: person_ids,
                       slot: { position_id: Position::ALPHA, begins_year: year })
                .order("slot.begins")
                .group_by(&:person_id)
                .transform_values { |rows| rows.map(&:slot) }
    end

    # Who is signed in to an Alpha shift right now.
    #
    # Year-scoped, unlike Timesheet.retrieve_signed_in_people and unlike
    # upstream: a never-closed Alpha timesheet from a past season would
    # otherwise mark someone checked in forever and add a stale option to the
    # shift filter.
    def signed_in_alphas(year)
      Timesheet.retrieve_signed_in_people(Position::ALPHA)
               .select { |_person_id, row| row.on_duty&.year == year }
    end

    def validate(rows, existing)
      pool_ids = assignable_mentor_ids

      rows.each_with_object({}) do |row, errors|
        message = row_error(row, pool_ids, existing[row.person_id] || [])
        errors[row.person_id] = message if message
      end.tap { |errors| annotate_unknown_mentors(errors) }
    end

    def row_error(row, pool_ids, stored)
      return "The mentors were not submitted correctly. Pick them from the lists again." if row.mentors_malformed
      return "Pick a status from the list." unless PersonMentor::ALPHA_STATUSES.include?(row.status)

      if row.mentor_ids.size != row.mentor_ids.uniq.size
        return "The same mentor is listed twice. Pick a different mentor, or leave the extra slot blank."
      end

      # A verdict with no one to attach it to is upstream's silent data loss:
      # its client drops the row from the payload and the verdict vanishes.
      if row.mentor_ids.empty? && row.status != PersonMentor::STATUS_PENDING
        return "Add at least one mentor before recording a result, or set the result back to pending."
      end

      # Mentors already stored for this person are grandfathered in: someone can
      # lose the Mentor position after a walk, and re-saving the row they are on
      # must not fail.
      allowed = pool_ids | stored.map(&:mentor_id).to_set
      unknown = row.mentor_ids.reject { |id| allowed.include?(id) }
      return unless unknown.any?

      # Filled in by annotate_unknown_mentors once every row has been checked,
      # so the callsigns cost one query rather than one per row.
      { unknown: }
    end

    # Turn the { unknown: [ids] } placeholders into readable messages.
    def annotate_unknown_mentors(errors)
      placeholders = errors.select { |_id, message| message.is_a?(Hash) }
      return if placeholders.empty?

      ids = placeholders.values.flat_map { |message| message[:unknown] }.uniq
      callsigns = Person.where(id: ids).pluck(:id, :callsign).to_h

      placeholders.each do |person_id, message|
        named = message[:unknown].map { |id| callsigns[id] || "person ##{id}" }
        errors[person_id] =
          "#{named.to_sentence} #{named.one? ? "does" : "do"} not hold the Mentor position. Pick a mentor from the list."
      end
    end

    # Reconcile one Alpha's stored mentors with what the sheet asks for.
    #
    # A minimal diff rather than upstream's delete-everything-and-recreate: the
    # end state is identical, but a mentor who stayed on the row keeps their
    # row, so the audit trail names the mentor who actually changed instead of
    # showing all three replaced.
    #
    # @return [Boolean] whether anything was written
    def sync_row(row, year, stored)
      desired = row.mentor_ids
      removed = stored.reject { |record| desired.include?(record.mentor_id) }
      kept = stored.select { |record| desired.include?(record.mentor_id) }
      added = desired - stored.map(&:mentor_id)

      restated = kept.select { |record| record.status != row.status }

      return false if removed.empty? && added.empty? && restated.empty?

      removed.each do |record|
        record.audit_reason = "mentor assignment removed"
        record.destroy!
      end

      restated.each do |record|
        record.audit_reason = "mentor status change"
        record.update!(status: row.status)
      end

      added.each do |mentor_id|
        PersonMentor.create!(person_id: row.person_id, mentor_id:, mentor_year: year,
                             position_id: Position::ALPHA, status: row.status) do |record|
          record.audit_reason = "mentor assignment"
        end
      end

      true
    end

    # Each of a shift's Alphas mapped to their pod's mentors, in pod order.
    #
    # The trio linkage is the alpha pod's mentor_pod_id -- Pod's own class
    # comment names this page as the reason that column is a contract. MITten
    # pods are not mentors and are left out, as upstream leaves them out.
    #
    # Pod membership is drawn from the whole mentor cadre while an assignment
    # may only name a Mentor-position holder, so the pod's members are narrowed
    # to the pool this page can actually record. Upstream copies them all, and
    # the ones with no matching option silently disappear from the row.
    #
    # @param pods [Array<Pod>] the shift's mentor and alpha pods
    # @return [Array(Hash, Array<Integer>)] alpha person id => mentor ids, and
    #   the pod mentors that could not be offered
    def pod_mentor_ids_by_alpha(pods)
      return [{}, []] if pods.empty?

      members = PersonPod.current.where(pod_id: pods.map(&:id)).ordered.pluck(:pod_id, :person_id)
                         .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

      assignable = assignable_mentor_ids
      mentor_pods = pods.select(&:mentor?)
      not_assignable = mentor_pods.flat_map { |pod| members[pod.id] || [] }
                                  .uniq.reject { |id| assignable.include?(id) }

      mentor_ids_by_pod = mentor_pods.to_h do |pod|
        [pod.id, (members[pod.id] || []).select { |id| assignable.include?(id) }]
      end

      mapping = pods.select(&:alpha?).each_with_object({}) do |alpha_pod, result|
        mentor_ids = mentor_ids_by_pod[alpha_pod.mentor_pod_id]
        next if mentor_ids.blank?

        (members[alpha_pod.id] || []).each { |person_id| result[person_id] = mentor_ids }
      end

      [mapping, not_assignable]
    end

    # The ids a mentor slot may hold: everyone with the Mentor position.
    def assignable_mentor_ids
      Person.joins(:person_position)
            .where(person_position: { position_id: Position::MENTOR })
            .pluck(:id)
            .to_set
    end

    def callsigns_for(person_ids)
      return [] if person_ids.empty?

      Person.where(id: person_ids).order(:callsign).pluck(:callsign)
    end
  end
end
