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

  def save(*rows, grants: {}) = assignment(*rows).save!(grants:)

  def assignment(*rows)
    shifts = ArtMentoring::Shifts.new(@training, YEAR)
    ArtMentoring::Assignment.new(shifts, shifts.group(@slot.id.to_s), rows.index_by(&:timesheet_id))
  end

  def row(sheet, *mentors, status: PersonMentor::STATUS_PENDING, notes: "")
    Row.new(timesheet_id: sheet.id, mentor_ids: mentors.compact.map(&:id), status:, notes:, mentor_malformed: false)
  end

  test "a pairing is recorded against the mentee's timesheet entry" do
    result = save(row(@first, @ferrous, status: PersonMentor::STATUS_PASS, notes: "Ready."))

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

  test "two mentors are two rows sharing the result and notes, and dropping one keeps the other" do
    result = save(row(@first, @ferrous, @cinder, status: PersonMentor::STATUS_PASS, notes: "Both agreed."))

    assert result.ok?
    assert_equal 1, result.saved_count
    rows = PersonMentor.where(timesheet_id: @first.id).order(:mentor_id)
    assert_equal [[@ferrous.id, PersonMentor::STATUS_PASS, "Both agreed."], [@cinder.id, PersonMentor::STATUS_PASS, "Both agreed."]].sort,
                 rows.map { |walk| [walk.mentor_id, walk.status, walk.notes] }.sort
    walk = ArtMentoring::Shifts.new(@training, YEAR).group(@slot.id.to_s).walk_for(@first)
    assert_equal [PersonMentor::STATUS_PASS, "Both agreed."], [walk.status, walk.notes]

    assert save(row(@first, @cinder, status: PersonMentor::STATUS_PASS, notes: "Both agreed.")).ok?
    assert_equal [@cinder.id], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id)
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

    notes_only = save(row(@second, nil, notes: "Seemed nervous."))
    assert_equal "Pick a mentor before writing notes.", notes_only.row_errors[@second.id]
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

    result = ArtMentoring::Assignment.new(shifts, group, { @first.id => row(@first, @ferrous) }).save!

    assert result.conflict
    assert_not result.ok?
    assert_equal [@ferrous.id], PersonMentor.where(timesheet_id: @first.id).pluck(:mentor_id)
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

  test "a pass already recorded is passed again, not newly" do
    walk(@first, @ferrous, status: PersonMentor::STATUS_PASS)

    pending = assignment(row(@first, @ferrous, status: PersonMentor::STATUS_PASS),
                         row(@second, @cinder, status: PersonMentor::STATUS_PASS))

    assert_equal [@second], pending.newly_passed
    assert_equal [@first, @second], pending.passed.sort_by(&:id)
  end
end
