# frozen_string_literal: true

# Records one mentoring shift: which mentors walked with each mentee, how the
# shift ended, and what was noted -- one person_mentor row per mentor per
# mentee timesheet entry, keyed by timesheet_id and mentor_id, the rows of one
# entry sharing the status and notes (an Alpha walk leaves timesheet_id NULL
# and is never touched here). A pass can also carry the grants the reader
# chose for it (ArtMentoring::Pass).
#
# Every row is checked before anything is written, and the shift is written in
# one transaction, grants included, so a refused row -- or a refused grant --
# means nothing was recorded and the page can say so.
class ArtMentoring::Assignment
  NOTES_MAX = 2_000
  # Mentors per mentee shift, as the Alpha roster allows.
  MENTOR_SLOTS = 3

  # One submitted row. `mentor_ids` is empty for "No mentor"; `mentor_malformed`
  # marks a value that was neither blank nor an id.
  Row = Data.define(:timesheet_id, :mentor_ids, :status, :notes, :mentor_malformed) do
    def passed? = status == PersonMentor::STATUS_PASS
  end

  # `row_errors` is keyed by timesheet id. `conflict` is a save that lost a race
  # to someone recording the same shift at the same moment; `denied` the reason
  # a grant was refused. Neither wrote anything. `granted` is what each pass did,
  # by person (ArtMentoring::Pass::Grant).
  Result = Data.define(:row_errors, :conflict, :denied, :saved_count, :cleared_count, :granted) do
    def ok? = row_errors.empty? && !conflict && denied.nil?
  end

  # @param shifts [ArtMentoring::Shifts] the year the group belongs to
  # @param group [ArtMentoring::Shifts::Group]
  # @param rows [Hash{Integer => Row}] keyed by timesheet id
  def initialize(shifts, group, rows)
    @shifts = shifts
    @group = group
    @entries = group.mentee_entries.index_by(&:id)
    # A row for anything but this shift's mentee entries is a hand-edited
    # request: the form only ever offers these.
    @rows = rows.values.select { |row| @entries.key?(row.timesheet_id) }
  end

  # @return [Hash{Integer => String}] by timesheet id
  def row_errors
    @row_errors ||= @rows.each_with_object({}) do |row, errors|
      message = row_error(row, @entries.fetch(row.timesheet_id))
      errors[row.timesheet_id] = message if message
    end
  end

  # The entries this save passes that were not passed before: the passes a
  # graduate-role holder is asked about.
  def newly_passed = passed - @group.passed

  # The entries this save records as passed, newly or again.
  def passed = @rows.select(&:passed?).map { |row| @entries.fetch(row.timesheet_id) }

  # @param grants [Hash{Integer => Hash}] by timesheet id: { join:, revoke: }
  # @return [Result]
  def save!(grants: {})
    return result(row_errors:) if row_errors.any?

    passed_by_id = passed.index_by(&:id)
    counts = Hash.new(0)
    granted = {}

    PersonMentor.transaction do
      @rows.each { |row| counts[sync(row, @entries.fetch(row.timesheet_id))] += 1 }

      # Only for a row this save records as passed: a grant rides on its pass.
      grants.each do |timesheet_id, choice|
        entry = passed_by_id[timesheet_id]
        next unless entry

        done = @shifts.pass.apply!(entry.person, join: choice[:join], revoke: choice[:revoke])
        next unless done.any?

        # A crafted request can answer for two of one person's entries.
        granted[entry.person] = granted.key?(entry.person) ? granted[entry.person].merge(done) : done
      end
    end
    result(saved_count: counts[:saved], cleared_count: counts[:cleared], granted:)
  rescue ActiveRecord::RecordNotUnique
    result(conflict: true)
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record.errors.of_kind?(:timesheet_id, :taken)

    result(conflict: true)
  rescue AuthorizationError => e
    result(denied: e.message)
  end

  private

  def result(row_errors: {}, conflict: false, denied: nil, saved_count: 0, cleared_count: 0, granted: {})
    Result.new(row_errors:, conflict:, denied:, saved_count:, cleared_count:, granted:)
  end

  def row_error(row, entry)
    return "Pick a result from the list." unless PersonMentor::STATUSES.include?(row.status)
    return "Notes can be at most #{NOTES_MAX} characters." if row.notes.length > NOTES_MAX
    return "Pick a mentor from the list." if row.mentor_malformed
    return "Pick each mentor once." if row.mentor_ids.uniq.size != row.mentor_ids.size
    return "A mentee has at most #{MENTOR_SLOTS} mentors." if row.mentor_ids.size > MENTOR_SLOTS

    if row.mentor_ids.empty?
      return "Pick a mentor before recording a result." unless row.status == PersonMentor::STATUS_PENDING
      return "Pick a mentor before writing notes." if row.notes.present?

      return nil
    end

    return "A mentee cannot be their own mentor." if row.mentor_ids.include?(entry.person_id)

    outsider = row.mentor_ids.find { |mentor_id| !assignable?(mentor_id, entry) }
    return nil unless outsider

    callsign = Person.where(id: outsider).pick(:callsign) || "Person ##{outsider}"
    title = @shifts.mentor_position&.title || "mentor"
    "#{callsign} does not hold the #{title} position. Pick a mentor from the list."
  end

  # The mentors on the shift and everyone holding the mentor position -- and a
  # mentor already recorded on this walk, who may have lost the position since.
  def assignable?(mentor_id, entry)
    @shifts.assignable_mentor_ids(@group).include?(mentor_id) || @group.walk_for(entry)&.mentor_ids&.include?(mentor_id)
  end

  # @return [Symbol, nil] :saved, :cleared, or nil when nothing changed
  def sync(row, entry)
    stored = (@group.walk_for(entry)&.rows || []).index_by(&:mentor_id)
    removed = stored.except(*row.mentor_ids).values.each do |walk|
      walk.audit_reason = "mentor assignment removed"
      walk.destroy!
    end
    return (:cleared if removed.any?) if row.mentor_ids.empty?

    written = row.mentor_ids.count do |mentor_id|
      walk = stored[mentor_id] || PersonMentor.new(person_id: entry.person_id, timesheet_id: entry.id, mentor_id:)
      # position_id and mentor_year too: a walk recorded under another ART's
      # mentee position, before its entry was corrected onto this one, is filed
      # here from now on (ArtMentoring::Shifts finds walks by entry).
      walk.assign_attributes(status: row.status, notes: row.notes.presence,
                             position_id: @shifts.mentee_position.id, mentor_year: @shifts.year)
      next false unless walk.changed?

      walk.audit_reason = audit_reason(walk)
      walk.save!
      true
    end
    :saved if written.positive? || removed.any?
  end

  def audit_reason(walk)
    return "mentor assignment" if walk.new_record? || walk.position_id_changed?
    return "mentor status change" if walk.status_changed?

    "mentor notes"
  end
end
