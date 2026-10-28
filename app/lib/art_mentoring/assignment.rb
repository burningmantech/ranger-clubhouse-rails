# frozen_string_literal: true

# Records one mentoring shift: which mentors walked with each mentee, how the
# shift ended, and what each mentor noted -- one person_mentor row per mentor
# per mentee timesheet entry, keyed by timesheet_id and mentor_id, the rows of
# one entry sharing the status, each with its own notes (ruled 2026-10-27; an
# Alpha walk leaves timesheet_id NULL and is never touched here). A pass can
# also carry the grants the reader chose for it (ArtMentoring::Pass), and a
# mentee a new general note (PersonMentoringNote): one roster, one Save.
#
# Every row is checked before anything is written, and the shift is written in
# one transaction, grants included, so a refused row -- or a refused grant --
# means nothing was recorded and the page can say so.
#
# A roster can stay open while someone else saves the shift (chosen
# 2026-10-27). Each row carries back the fingerprint of the walk the page was
# drawn with (Row#was): a row left as drawn stands for what is stored now, so
# the other save's work stays, and a row changed here and there both is refused.
class ArtMentoring::Assignment
  NOTES_MAX = 2_000
  # Mentors per mentee shift, as the Alpha roster allows.
  MENTOR_SLOTS = 3

  # One submitted row: its mentor slots in the form's order, blank ones
  # included (ArtMentoring::Shifts::WalkMentor), the result they share, and
  # the fingerprint of the walk the page was drawn with (nil when none was
  # sent). `mentor_malformed` marks slots sent in any shape but the form's, or
  # a slot value that was neither blank nor an id.
  Row = Data.define(:timesheet_id, :mentors, :status, :mentor_malformed, :was) do
    def passed? = status == PersonMentor::STATUS_PASS
    def mentor_ids = mentors.filter_map(&:id)
    def notes_for(mentor_id) = mentors.find { |mentor| mentor.id == mentor_id }&.notes.to_s
    def fingerprint = ArtMentoring::Assignment.fingerprint(status, mentors)
  end

  # `row_errors` is keyed by timesheet id. `conflict` is a save that lost a race
  # to someone recording the same shift at the same moment; `denied` the reason
  # a grant was refused. Neither wrote anything. `noted_count` is the general
  # notes added; `granted` is what each pass did, by person
  # (ArtMentoring::Pass::Grant).
  Result = Data.define(:row_errors, :conflict, :denied, :saved_count, :cleared_count, :noted_count, :granted) do
    def ok? = row_errors.empty? && !conflict && denied.nil?
  end

  # Notes as they are checked, compared and stored. A form sends each line
  # break as CR LF; the textarea's maxlength counted it as one, and so does the
  # length check.
  def self.clean(text) = text.to_s.gsub("\r\n", "\n").strip

  # A walk's result and each mentor with their notes, in no order, as one
  # digest: what the roster draws into each row (Row#was), and what a save
  # compares with the walk as stored by then.
  def self.fingerprint(status, mentors)
    # A blank slot's notes count too: typed with no mentor, they are a change.
    pairs = mentors.filter_map do |mentor|
      notes = clean(mentor.notes)
      [mentor.id.to_i, notes] if mentor.id || notes.present?
    end
    Digest::SHA256.hexdigest([status, pairs.sort].to_json)
  end

  # A stored walk's fingerprint. An entry with none is drawn Pending, with no
  # mentor.
  def self.stored_fingerprint(walk) = fingerprint(walk&.status || PersonMentor::STATUS_PENDING, walk&.mentors || [])

  # @param shifts [ArtMentoring::Shifts] the year the group belongs to
  # @param group [ArtMentoring::Shifts::Group]
  # @param rows [Hash{Integer => Row}] keyed by timesheet id
  # @param general_notes [Hash{Integer => String}] a new general note, by mentee person id
  def initialize(shifts, group, rows, general_notes: {})
    @shifts = shifts
    @group = group
    @entries = group.mentee_entries.index_by(&:id)
    # A row for anything but this shift's mentee entries is a hand-edited
    # request: the form only ever offers these.
    @submitted = rows.values.select { |row| @entries.key?(row.timesheet_id) }
    @rows = @submitted.map { |row| drawn?(row) ? stored_row(row) : row }
    @first_entries = group.first_entries.index_by(&:person_id)
    # By person. The form offers a box for each of the shift's mentees, and a
    # note typed for one moved to another shift since the page was drawn is
    # still added: a general note is tied to no shift. A note about anyone but
    # the year's mentees is a hand-edited request.
    mentees = shifts.mentee_entries.to_h { |entry| [entry.person_id, entry.person] }
    @general_notes = general_notes.filter_map { |person_id, notes| [mentees[person_id], notes] if mentees[person_id] }.to_h
  end

  # @return [Hash{Integer => String}] by timesheet id; a refused general note
  #   under its mentee's first entry, where the roster shows it, unless that
  #   entry's row has an error of its own
  def row_errors = @row_errors ||= general_note_errors.merge(entry_errors)

  # What a refused or questioned save shows again as typed, by timesheet id. A
  # row left as drawn, one that could not be read and one someone else saved in
  # the meantime show what is stored instead, so a second Save cannot write
  # what the reader never saw.
  def typed_rows
    @submitted.reject { |row| drawn?(row) || row.mentor_malformed || stale?(row) }.index_by(&:timesheet_id)
  end

  # The entries this save passes that were not passed before: the passes a
  # graduate-role holder is asked about.
  def newly_passed = passed - @group.passed

  # The entries this save records as passed, newly or again.
  def passed = @rows.select(&:passed?).map { |row| @entries.fetch(row.timesheet_id) }

  # The entries this save passes with no mentor selected, unless already
  # recorded so: the roster asks before recording one (owner, 2026-10-28).
  def passed_without_mentor
    @rows.filter_map do |row|
      next unless row.passed? && row.mentor_ids.empty?

      entry = @entries.fetch(row.timesheet_id)
      walk = @group.walk_for(entry)
      entry unless walk&.status == PersonMentor::STATUS_PASS && walk.without_mentor?
    end
  end

  # @param written_by [Person] who wrote the general notes
  # @param grants [Hash{Integer => Hash}] by timesheet id: { join:, revoke: }
  # @param record_without_mentor [Boolean] false leaves each #passed_without_mentor
  #   row as stored -- promoted without a verdict (owner, 2026-10-28) -- while
  #   its grants still apply
  # @return [Result]
  def save!(written_by:, grants: {}, record_without_mentor: true)
    return result(row_errors:) if row_errors.any?

    passed_by_id = passed.index_by(&:id)
    unrecorded = record_without_mentor ? [] : passed_without_mentor.map(&:id)
    counts = Hash.new(0)
    granted = {}

    PersonMentor.transaction do
      @rows.each do |row|
        counts[sync(row, @entries.fetch(row.timesheet_id))] += 1 unless unrecorded.include?(row.timesheet_id)
      end
      @general_notes.each do |person, notes|
        next if PersonMentoringNote.resubmitted?(person:, written_by:, notes:)

        PersonMentoringNote.create!(person:, written_by:, notes:)
        counts[:noted] += 1
      end

      # Only for a row this save passes: a grant rides on its pass, recorded or
      # -- promoted without a verdict -- not.
      grants.each do |timesheet_id, choice|
        entry = passed_by_id[timesheet_id]
        next unless entry

        done = @shifts.pass.apply!(entry.person, join: choice[:join], revoke: choice[:revoke])
        next unless done.any?

        # A crafted request can answer for two of one person's entries.
        granted[entry.person] = granted.key?(entry.person) ? granted[entry.person].merge(done) : done
      end
    end
    result(saved_count: counts[:saved], cleared_count: counts[:cleared], noted_count: counts[:noted], granted:)
  rescue ActiveRecord::RecordNotUnique
    result(conflict: true)
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record.errors.of_kind?(:timesheet_id, :taken)

    result(conflict: true)
  rescue AuthorizationError => e
    result(denied: e.message)
  end

  private

  def result(row_errors: {}, conflict: false, denied: nil, saved_count: 0, cleared_count: 0, noted_count: 0, granted: {})
    Result.new(row_errors:, conflict:, denied:, saved_count:, cleared_count:, noted_count:, granted:)
  end

  # Left as the page drew it.
  def drawn?(row) = row.was.present? && row.fingerprint == row.was

  # A row left as drawn, as its walk is stored now: whatever someone else saved
  # since stands.
  def stored_row(row)
    walk = @group.walk_for(@entries.fetch(row.timesheet_id))
    row.with(mentors: walk&.mentors || [], status: walk&.status || PersonMentor::STATUS_PENDING)
  end

  # Changed here and, since the page was drawn, by someone else -- unless the
  # two made the same change.
  def stale?(row)
    return false if row.was.blank?

    now = self.class.stored_fingerprint(@group.walk_for(@entries.fetch(row.timesheet_id)))
    row.was != now && row.fingerprint != now
  end

  def entry_errors
    @rows.each_with_object({}) do |row, errors|
      message = row_error(row, @entries.fetch(row.timesheet_id))
      errors[row.timesheet_id] = message if message
    end
  end

  def general_note_errors
    @general_notes.filter_map do |person, notes|
      next if notes.length <= PersonMentoringNote::NOTES_MAX

      # A mentee moved off the shift has no row here to show it under.
      [@first_entries[person.id]&.id, "A general note can be at most #{PersonMentoringNote::NOTES_MAX} characters."]
    end.to_h
  end

  def row_error(row, entry)
    # These two show what is stored again, not what was typed (#typed_rows).
    if row.mentor_malformed
      return "This row could not be read, so it shows what is saved now. Make your change again, then save."
    end
    if stale?(row)
      return "Someone else saved this mentee after you opened the page, so it shows what they saved. Make your " \
             "change again, then save."
    end
    return "Pick a result from the list." unless PersonMentor::STATUSES.include?(row.status)

    # Asked before any other slot's error, which would draw the box beside its
    # new mentor and so answer the question unasked.
    walk = @group.walk_for(entry)
    row.mentors.each.with_index(1) do |mentor, slot|
      return moved_notes_error(slot, mentor) if moved_notes?(mentor, walk)
    end
    # Numbered as the roster labels the boxes: "Mentor 2 Notes".
    row.mentors.each.with_index(1) do |mentor, slot|
      return "Notes for mentor #{slot} can be at most #{NOTES_MAX} characters." if mentor.notes.length > NOTES_MAX
      return "Notes for mentor #{slot} need a mentor. Pick one, or clear the notes." if !mentor.id && mentor.notes.present?
    end
    return "Pick each mentor once." if row.mentor_ids.uniq.size != row.mentor_ids.size
    return "A mentee has at most #{MENTOR_SLOTS} mentors." if row.mentor_ids.size > MENTOR_SLOTS

    if row.mentor_ids.empty?
      # A pass may be recorded without one; the roster asks first (owner, 2026-10-28).
      return "Pick a mentor before recording a result." unless row.status == PersonMentor::STATUS_PENDING || row.passed?

      return nil
    end

    return "A mentee cannot be their own mentor." if row.mentor_ids.include?(entry.person_id)

    outsider = row.mentor_ids.find { |mentor_id| !assignable?(mentor_id, entry) }
    return nil unless outsider

    callsign = Person.where(id: outsider).pick(:callsign) || "Person ##{outsider}"
    title = @shifts.mentor_position&.title || "mentor"
    "#{callsign} does not hold the #{title} position. Pick a mentor from the list."
  end

  # A box still holding what the mentor its slot showed had noted, now beside
  # another mentor: saved, one mentor's words would be filed as another's. It is
  # asked once (chosen 2026-10-27): the refused page draws the box beside its
  # new mentor, so saving it again keeps the notes there.
  def moved_notes?(mentor, walk)
    return false if mentor.id.nil? || mentor.loaded_id.nil? || mentor.id == mentor.loaded_id || mentor.notes.blank?

    held = walk&.mentors&.find { |stored| stored.id == mentor.loaded_id }
    !held.nil? && self.class.clean(held.notes) == mentor.notes
  end

  def moved_notes_error(slot, mentor)
    names = Person.where(id: [mentor.loaded_id, mentor.id]).pluck(:id, :callsign).to_h
    before, after = [mentor.loaded_id, mentor.id].map { |id| names[id] || "Person ##{id}" }
    "Mentor #{slot} changed from #{before} to #{after}, but its notes are #{before}'s. Save again to keep them as " \
      "#{after}'s, or change them first."
  end

  # The mentors on the shift and everyone holding the mentor position -- and a
  # mentor already recorded on this walk, who may have lost the position since.
  def assignable?(mentor_id, entry)
    @shifts.assignable_mentor_ids(@group).include?(mentor_id) || @group.walk_for(entry)&.mentor_ids&.include?(mentor_id)
  end

  # @return [Symbol, nil] :saved, :cleared, or nil when nothing changed
  def sync(row, entry)
    stored = (@group.walk_for(entry)&.rows || []).index_by(&:mentor_id)
    # A pass with no mentor is one row naming none (owner, 2026-10-28).
    mentor_ids = row.mentor_ids.empty? && row.passed? ? [nil] : row.mentor_ids
    removed = stored.except(*mentor_ids).values.each do |walk|
      walk.audit_reason = "mentor assignment removed"
      walk.destroy!
    end
    return (:cleared if removed.any?) if mentor_ids.empty?

    written = mentor_ids.count do |mentor_id|
      walk = stored[mentor_id] || PersonMentor.new(person_id: entry.person_id, timesheet_id: entry.id, mentor_id:)
      # position_id and mentor_year too: a walk recorded under another ART's
      # mentee position, before its entry was corrected onto this one, is filed
      # here from now on (ArtMentoring::Shifts finds walks by entry).
      walk.assign_attributes(status: row.status, notes: row.notes_for(mentor_id).presence,
                             position_id: @shifts.mentee_position.id, mentor_year: @shifts.year)
      next false unless walk.changed?

      walk.audit_reason = audit_reason(walk)
      walk.save!
      true
    end
    :saved if written.positive? || removed.any?
  end

  def audit_reason(walk)
    return "pass recorded without a mentor" if walk.new_record? && walk.mentor_id.nil?
    return "mentor assignment" if walk.new_record? || walk.position_id_changed?
    return "mentor status change" if walk.status_changed?

    "mentor notes"
  end
end
