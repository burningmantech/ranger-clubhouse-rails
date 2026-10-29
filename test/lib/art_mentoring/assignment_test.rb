# frozen_string_literal: true

require "test_helper"

# Recording one mentoring shift (ArtMentoring::Assignment): one person_mentor
# row per mentor per mentee timesheet entry, every row checked before any is
# written, and the whole shift written together.
class ArtMentoring::AssignmentTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role
  include ArtMentoringTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  Row = ArtMentoring::Assignment::Row
  Mentor = ArtMentoring::Shifts::WalkMentor

  setup do
    travel_to Time.zone.local(YEAR, 9, 2, 19, 0, 0)
    Current.reset
    setup_art_mentoring
    @slot = mentee_shift(Time.zone.local(YEAR, 9, 1, 17, 45, 0))
    @tinsel = create_person("Tinsel")
    @moonrake = create_person("Moonrake")
    @ferrous = create_person("Ferrous")
    @cinder = create_person("Cinder")
    hold_mentor_position(@ferrous, @cinder)
    @first = mentee_entry(@tinsel, @slot.begins, off_duty: @slot.ends, slot: @slot)
    @second = mentee_entry(@moonrake, @slot.begins, off_duty: @slot.ends, slot: @slot)
  end

  teardown do
    Current.reset
    travel_back
  end

  # Cinder writes the general notes.
  def save(*rows, grants: {}, general_notes: {}) = assignment(*rows, general_notes:).save!(written_by: @cinder, grants:)

  def assignment(*rows, general_notes: {})
    shifts = ArtMentoring::Shifts.new(@training, YEAR)
    ArtMentoring::Assignment.new(shifts, shifts.group(@slot.id.to_s), rows.index_by(&:timesheet_id), general_notes:)
  end

  # A submitted row. Each mentor slot is a person, nil for "No mentor", or
  # [person or nil, their notes, whom the slot showed when the page was drawn
  # (the person themself when not given)]. `was` is the walk's fingerprint as
  # drawn.
  def row(sheet, *slots, status: PersonMentor::STATUS_PENDING, was: nil)
    mentors = slots.map do |slot|
      person, notes, loaded = slot.is_a?(Array) ? slot : [slot, ""]
      Mentor.new(id: person&.id, notes:, loaded_id: (loaded || person)&.id)
    end
    Row.new(timesheet_id: sheet.id, mentors:, status:, mentor_malformed: false, was:)
  end

  test "a pairing is recorded against the mentee's timesheet entry" do
    result = save(row(@first, [@ferrous, "Ready."], status: PersonMentor::STATUS_PASS))

    assert result.ok?
    assert_equal 1, result.saved_count
    walk = PersonMentor.find_by!(timesheet_id: @first.id)
    assert_equal [@tinsel.id, @ferrous.id, YEAR, @mentee_position.id, PersonMentor::STATUS_PASS, "Ready."],
                 [walk.person_id, walk.mentor_id, walk.mentor_year, walk.position_id, walk.status, walk.notes]
    assert_equal ["mentor assignment"], ActionLog.where(event: "person-mentor-create").pluck(:message),
                 "the walk is audited"
  end

  test "a new mentor replaces the old one on the same row" do
    walk(@first, @ferrous)

    assert save(row(@first, @cinder)).ok?

    assert_equal [@cinder.id], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id)
  end

  test "two mentors are two rows sharing the result, each with its own notes, and dropping one keeps the other" do
    result = save(row(@first, [@ferrous, "Ready."], [@cinder, "Calm on the radio."], status: PersonMentor::STATUS_PASS))

    assert result.ok?
    assert_equal 1, result.saved_count
    rows = PersonMentor.where(timesheet_id: @first.id)
    assert_equal [[@ferrous.id, PersonMentor::STATUS_PASS, "Ready."], [@cinder.id, PersonMentor::STATUS_PASS, "Calm on the radio."]].sort,
                 rows.map { |walk| [walk.mentor_id, walk.status, walk.notes] }.sort
    walk = ArtMentoring::Shifts.new(@training, YEAR).group(@slot.id.to_s).walk_for(@first)
    assert_equal PersonMentor::STATUS_PASS, walk.status
    assert_equal [[@ferrous.id, "Ready."], [@cinder.id, "Calm on the radio."]].sort,
                 walk.mentors.map { |mentor| [mentor.id, mentor.notes] }.sort

    assert save(row(@first, [@cinder, "Calm on the radio."], status: PersonMentor::STATUS_PASS)).ok?
    assert_equal [@cinder.id], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id)
  end

  test "a mentor's notes are refused by the number of their box" do
    long = "a" * (ArtMentoring::Assignment::NOTES_MAX + 1)

    assert_equal "Notes for mentor 2 can be at most 2000 characters.",
                 save(row(@first, @ferrous, [@cinder, long])).row_errors[@first.id]
    assert_equal "Notes for mentor 3 need a mentor. Pick one, or clear the notes.",
                 save(row(@first, @ferrous, nil, [nil, "Seemed nervous."])).row_errors[@first.id]
  end

  test "one mentor picked twice, or more than the slots allow, is refused" do
    assert_equal "Pick each mentor once.", save(row(@first, @ferrous, @ferrous)).row_errors[@first.id]

    fourth = create_person("Quill")
    fifth = create_person("Brine")
    hold_mentor_position(fourth, fifth)
    assert_equal "A mentee has at most 3 mentors.",
                 save(row(@first, @ferrous, @cinder, fourth, fifth)).row_errors[@first.id]
  end

  test "No mentor with nothing else recorded clears the pairing" do
    walk(@first, @ferrous)

    result = save(row(@first, nil))

    assert_equal 1, result.cleared_count
    assert_not PersonMentor.exists?(timesheet_id: @first.id)
  end

  test "an unchanged row writes nothing" do
    walk(@first, @ferrous)

    result = save(row(@first, @ferrous))

    assert result.ok?
    assert_equal 0, result.saved_count + result.cleared_count
  end

  test "a result or notes with no mentor are refused, and nothing on the shift is written" do
    result = save(row(@first, @ferrous), row(@second, nil, status: PersonMentor::STATUS_BONK))

    assert_not result.ok?
    assert_equal({ @second.id => "Pick a mentor before recording a result." }, result.row_errors)
    assert_not PersonMentor.exists?(timesheet_id: @first.id), "the valid row waits for the refused one"

    notes_only = save(row(@second, [nil, "Seemed nervous."]))
    assert_equal "Notes for mentor 1 need a mentor. Pick one, or clear the notes.", notes_only.row_errors[@second.id]
  end

  test "someone outside the mentor position is refused by name" do
    outsider = create_person("Wanderer")

    result = save(row(@first, outsider))

    assert_equal "Wanderer does not hold the Green Dot Mentor position. Pick a mentor from the list.",
                 result.row_errors[@first.id]
  end

  test "a recorded mentor stays recordable after losing the position" do
    walk(@first, @ferrous)
    PersonPosition.where(person_id: @ferrous.id).delete_all

    assert save(row(@first, @ferrous, status: PersonMentor::STATUS_PASS)).ok?
    assert_equal PersonMentor::STATUS_PASS, PersonMentor.find_by!(timesheet_id: @first.id).status
  end

  test "a mentee cannot be their own mentor, and a made-up result is refused" do
    hold_mentor_position(@tinsel)

    assert_equal "A mentee cannot be their own mentor.", save(row(@first, @tinsel)).row_errors[@first.id]
    assert_equal "Pick a result from the list.", save(row(@first, @ferrous, status: "promoted")).row_errors[@first.id]
  end

  test "a row for an entry outside the shift is ignored" do
    elsewhere = mentee_entry(create_person("Drifter"), @slot.begins + 1.day, off_duty: @slot.ends + 1.day)

    result = save(row(elsewhere, @ferrous))

    assert result.ok?
    assert_not PersonMentor.exists?(timesheet_id: elsewhere.id)
  end

  test "one mentor walking one mentee twice in a year is two rows, and an Alpha row is left alone" do
    later = mentee_shift(@slot.begins + 1.day)
    again = mentee_entry(@tinsel, later.begins, off_duty: later.ends, slot: later)
    alpha = PersonMentor.create!(person: @tinsel, mentor: @ferrous, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    walk(again, @ferrous, status: PersonMentor::STATUS_PASS)

    assert save(row(@first, @ferrous)).ok?

    assert_equal 2, PersonMentor.where(person_id: @tinsel.id, position_id: @mentee_position.id).count
    assert_equal PersonMentor::STATUS_PASS, alpha.reload.status
  end

  # Timesheet Management can correct an entry's position after it was walked.
  test "a walk recorded under another mentee position moves here with its entry" do
    other = Position.create!(title: "Troubleshooter Prospective", type: Position::TYPE_FRONTLINE, active: true)
    PersonMentor.create!(person_id: @tinsel.id, mentor: @ferrous, mentor_year: YEAR, position_id: other.id,
                         timesheet_id: @first.id, status: PersonMentor::STATUS_PENDING)

    shifts = ArtMentoring::Shifts.new(@training, YEAR)
    assert_equal [@ferrous.id], shifts.group(@slot.id.to_s).walk_for(@first).mentor_ids

    assert save(row(@first, @ferrous)).ok?
    assert_equal [@mentee_position.id], PersonMentor.where(timesheet_id: @first.id).pluck(:position_id)
  end

  # Two people recording one shift at once: the same mentor twice is the
  # database's refusal, reported; a different mentor is simply added alongside.
  test "a shift saved by someone else in the meantime is reported, not raised" do
    shifts = ArtMentoring::Shifts.new(@training, YEAR)
    group = shifts.group(@slot.id.to_s)
    walk(@first, @ferrous) # recorded after this save read the shift

    result = ArtMentoring::Assignment.new(shifts, group, { @first.id => row(@first, @ferrous) }).save!(written_by: @cinder)

    assert result.conflict
    assert_not result.ok?
    assert_equal [@ferrous.id], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id)
  end

  # A roster open while someone else saves the shift (chosen 2026-10-27).
  test "a row left as drawn keeps what someone else saved since, and one changed both ways is refused" do
    drawn = ArtMentoring::Assignment.stored_fingerprint(nil) # no walk yet when the page was drawn
    walk(@first, @ferrous, notes: "Ready.") # saved by someone else after that

    assert save(row(@first, nil, was: drawn)).ok?
    assert_equal [[@ferrous.id, "Ready."]], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id, :notes)

    assert save(row(@first, [@ferrous, "Ready."], was: drawn)).ok?, "the same change made twice is no conflict"

    stale = assignment(row(@first, [@cinder, "Calm on the radio."], was: drawn))
    assert_equal "Someone else saved this mentee after you opened the page, so it shows what they saved. Make your " \
                 "change again, then save.", stale.row_errors[@first.id]
    assert_empty stale.typed_rows, "the row comes back as stored, not as typed"
    assert_equal [@ferrous.id], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id)
  end

  test "notes typed beside No mentor are a change, never read as a row left as drawn" do
    drawn = ArtMentoring::Assignment.stored_fingerprint(nil)

    assert_equal "Notes for mentor 1 need a mentor. Pick one, or clear the notes.",
                 save(row(@first, [nil, "Seemed nervous."], was: drawn)).row_errors[@first.id]
  end

  test "a slot changed to another mentor asks once before the notes in its box go with them" do
    walk(@first, @ferrous, notes: "Ready.")

    asked = save(row(@first, [@cinder, "Ready.", @ferrous]))
    assert_equal "Mentor 1 changed from Ferrous to Cinder, but its notes are Ferrous's. Save again to keep them as " \
                 "Cinder's, or change them first.", asked.row_errors[@first.id]
    assert_equal [@ferrous.id], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id)

    assert save(row(@first, [@cinder, "Ready.", @cinder])).ok?, "the refused page drew the box beside Cinder"
    assert_equal [[@cinder.id, "Ready."]], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id, :notes)
  end

  test "notes rewritten for a slot's new mentor go with them at once" do
    walk(@first, @ferrous, notes: "Ready.")

    assert save(row(@first, [@cinder, "Calm on the radio.", @ferrous])).ok?

    assert_equal [[@cinder.id, "Calm on the radio."]], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id, :notes)
  end

  # ---------------------------------------------------------- general notes

  test "a general note is written with the shift, by its author" do
    result = save(row(@first, @ferrous), general_notes: { @tinsel.id => "Ask about the radio." })

    assert result.ok?
    assert_equal 1, result.noted_count
    note = PersonMentoringNote.find_by!(person_id: @tinsel.id)
    assert_equal ["Ask about the radio.", @cinder.id], [note.notes, note.written_by_id]
  end

  test "a general note over the limit is refused under the mentee's first entry, and nothing is written" do
    long = "a" * (PersonMentoringNote::NOTES_MAX + 1)

    result = save(row(@first, @ferrous), general_notes: { @moonrake.id => long })

    assert_equal({ @second.id => "A general note can be at most 2000 characters." }, result.row_errors)
    assert_not PersonMentor.exists?(timesheet_id: @first.id)
    assert_not PersonMentoringNote.exists?
  end

  test "a general note for someone who is not one of the year's mentees is ignored" do
    result = save(row(@first, @ferrous), general_notes: { @ferrous.id => "Not a mentee here." })

    assert result.ok?
    assert_equal 0, result.noted_count
    assert_not PersonMentoringNote.exists?
  end

  test "a general note typed for a mentee moved to another shift since is still added" do
    later = mentee_shift(@slot.begins + 1.day)
    moved = mentee_entry(create_person("Drifter"), later.begins, off_duty: later.ends, slot: later)

    result = save(row(@first, @ferrous), general_notes: { moved.person_id => "Moved to the next shift." })

    assert result.ok?
    assert_equal ["Moved to the next shift."], PersonMentoringNote.where(person_id: moved.person_id).pluck(:notes)
  end

  test "a resubmitted general note is added once, and the same words on a later day are a new note" do
    notes = { @tinsel.id => "Ask about the radio." }

    assert_equal 1, save(row(@first, @ferrous), general_notes: notes).noted_count
    assert_equal 0, save(row(@first, @ferrous), general_notes: notes).noted_count
    assert_equal 1, PersonMentoringNote.where(person_id: @tinsel.id).count

    travel PersonMentoringNote::RESUBMIT_WITHIN + 1.minute
    assert_equal 1, save(row(@first, @ferrous), general_notes: notes).noted_count
  end

  # ---------------------------------------------------------- pass grants

  test "a pass's grants are written with it, and only for a row recorded as passed" do
    recommended_position("Dirt - Green Dot")
    hold_mentee_position(@tinsel)
    hold_mentee_position(@moonrake)

    result = save(row(@first, @ferrous, status: PersonMentor::STATUS_PASS), row(@second, @cinder),
                  grants: { @first.id => { join: true, revoke: true }, @second.id => { join: true, revoke: true } })

    assert result.ok?
    assert_equal({ @tinsel => ArtMentoring::Pass::Grant.new(joined: true, revoked: [@mentee_position]) }, result.granted)
    assert PersonTeam.exists?(team_id: @training.team_id, person_id: @tinsel.id)
    assert_not PersonPosition.exists?(person_id: @tinsel.id, position_id: @mentee_position.id)
    assert_not PersonTeam.exists?(team_id: @training.team_id, person_id: @moonrake.id),
               "Moonrake's row is pending, so the grant offered for it does nothing"
  end

  test "a refused grant records nothing, not even the pass" do
    ensure_role(Role::ADMIN, "Admin")
    TeamRole.create!(team_id: @training.team_id, role_id: Role::ADMIN)

    result = save(row(@first, @ferrous, status: PersonMentor::STATUS_PASS),
                  grants: { @first.id => { join: true, revoke: false } })

    assert_not result.ok?
    assert_match "Admin permission", result.denied
    assert_not PersonMentor.exists?(timesheet_id: @first.id)
  end

  test "grants sent for two entries of one mentee are reported together" do
    hold_mentee_position(@tinsel)
    again = mentee_entry(@tinsel, @slot.begins + 30.minutes, off_duty: @slot.ends, slot: @slot)

    result = save(row(@first, @ferrous, status: PersonMentor::STATUS_PASS),
                  row(again, @ferrous, status: PersonMentor::STATUS_PASS),
                  grants: { @first.id => { join: true, revoke: false }, again.id => { join: false, revoke: true } })

    assert result.ok?
    assert_equal({ @tinsel => ArtMentoring::Pass::Grant.new(joined: true, revoked: [@mentee_position]) }, result.granted)
  end

  # ------------------------------------------- a pass with no mentor

  test "a pass with no mentor is one row naming none, until a mentor is picked" do
    pass = row(@first, nil, status: PersonMentor::STATUS_PASS)
    assert_equal [@first], assignment(pass).passed_without_mentor

    assert save(pass).ok?
    assert_equal [[nil, PersonMentor::STATUS_PASS]], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id, :status)
    assert_empty assignment(pass).passed_without_mentor, "recorded so, it is not asked about again"
    assert_equal 0, save(pass).saved_count, "and saved again unchanged, it writes nothing"

    save(row(@first, @ferrous, status: PersonMentor::STATUS_PASS))
    assert_equal [@ferrous.id], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id)
  end

  test "promoted without a verdict, a pass with no mentor records nothing but its grants" do
    hold_mentee_position(@tinsel)

    result = assignment(row(@first, nil, status: PersonMentor::STATUS_PASS))
             .save!(written_by: @cinder, grants: { @first.id => { join: true, revoke: true } }, without_verdict: true)

    assert result.ok?
    assert_equal 0, result.saved_count
    assert_not PersonMentor.exists?(timesheet_id: @first.id)
    assert PersonTeam.exists?(team_id: @training.team_id, person_id: @tinsel.id)
    assert_not PersonPosition.exists?(person_id: @tinsel.id, position_id: @mentee_position.id)
  end

  test "promoted without a verdict, a pass with no mentor that no grant promotes is recorded" do
    hold_mentee_position(@tinsel)

    result = assignment(row(@first, nil, status: PersonMentor::STATUS_PASS), row(@second, nil, status: PersonMentor::STATUS_PASS))
             .save!(written_by: @cinder, grants: { @first.id => { join: true, revoke: true } }, without_verdict: true)

    assert result.ok?
    assert_not PersonMentor.exists?(timesheet_id: @first.id), "Tinsel was promoted, with no verdict"
    assert_equal [[nil, PersonMentor::STATUS_PASS]], PersonMentor.where(timesheet_id: @second.id).pluck(:mentor_id, :status),
                 "Moonrake gained nothing, so the pass typed for them stands"
  end

  # Another graduate's grant committing between this one's check and its write.
  test "a promote that loses a race to another grant is a conflict, not an error" do
    shifts = ArtMentoring::Shifts.new(@training, YEAR)
    shifts.pass.define_singleton_method(:apply!) { |*, **| raise ActiveRecord::RecordNotUnique, "Duplicate entry" }
    promoting = ArtMentoring::Assignment.new(shifts, shifts.group(@slot.id.to_s), {})

    result = promoting.promote!(grants: { @first.id => { join: true, revoke: true } })

    assert result.conflict
    assert_not result.ok?
  end

  test "promoting without a verdict grants for any of the shift's mentees and writes no walk" do
    hold_mentee_position(@moonrake)

    result = assignment(row(@first, @ferrous, status: PersonMentor::STATUS_PASS), row(@second, nil))
             .promote!(grants: { @second.id => { join: true, revoke: true } })

    assert result.ok?
    assert_equal({ @moonrake => ArtMentoring::Pass::Grant.new(joined: true, revoked: [@mentee_position]) }, result.granted)
    assert_not PersonMentor.exists?(timesheet_id: [@first.id, @second.id]), "not even the row typed as passed"
  end

  test "a pass already recorded is passed again, not newly" do
    walk(@first, @ferrous, status: PersonMentor::STATUS_PASS)

    pending = assignment(row(@first, @ferrous, status: PersonMentor::STATUS_PASS),
                         row(@second, @cinder, status: PersonMentor::STATUS_PASS))

    assert_equal [@second], pending.newly_passed
    assert_equal [@first, @second], pending.passed.sort_by(&:id)
  end
end
