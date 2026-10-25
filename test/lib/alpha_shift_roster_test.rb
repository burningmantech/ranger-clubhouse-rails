# frozen_string_literal: true

require "test_helper"

class AlphaShiftRosterTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)

    @slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 26, 18, 0, 0),
                        description: "Wednesday Day", max: 3)

    # Deliberately created out of callsign order to prove the sort.
    @zed = create_person("ZedAlpha", status: Person::ALPHA)
    @abe = create_person("abeAlpha", status: Person::ALPHA)
    [@zed, @abe].each { |person| PersonSlot.create!(person_id: person.id, slot_id: @slot.id) }
  end

  teardown do
    Current.reset
    travel_back
  end

  test "shifts_for_year counts sign-ups and reports capacity" do
    shifts = AlphaShiftRoster.shifts_for_year(YEAR)

    assert_equal 1, shifts.size
    shift = shifts.first
    assert_equal 2, shift.signed_up
    assert_equal 0, shift.signed_in
    assert_not shift.full?
  end

  test "a shift at capacity reports full" do
    third = create_person("MidAlpha", status: Person::ALPHA)
    PersonSlot.create!(person_id: third.id, slot_id: @slot.id)

    assert AlphaShiftRoster.shifts_for_year(YEAR).first.full?
  end

  test "a slot with no maximum is never full" do
    @slot.update!(max: 0)

    assert_not AlphaShiftRoster.shifts_for_year(YEAR).first.full?
  end

  test "inactive shifts are listed rather than filtered out" do
    @slot.update!(active: false)

    assert_equal 1, AlphaShiftRoster.shifts_for_year(YEAR).size
  end

  test "shifts from other years are excluded" do
    create_slot(@alpha_position, begins: Time.zone.local(YEAR - 1, 8, 26, 8, 0, 0),
                ends: Time.zone.local(YEAR - 1, 8, 26, 18, 0, 0), description: "Last year")

    assert_equal 1, AlphaShiftRoster.shifts_for_year(YEAR).size
  end

  test "for_slot sorts entries by callsign regardless of case" do
    roster = AlphaShiftRoster.for_slot(@slot)

    assert_equal %w[abeAlpha ZedAlpha], roster.entries.map { |entry| entry.person.callsign }
  end

  test "an empty shift returns an empty roster rather than failing" do
    PersonSlot.where(slot_id: @slot.id).delete_all

    roster = AlphaShiftRoster.for_slot(@slot)

    assert_empty roster.entries
    assert_not roster.any_signed_in?
    assert_equal 0, roster.signed_in_count
  end

  test "an open Alpha timesheet marks someone signed in" do
    Timesheet.create!(person_id: @zed.id, position_id: Position::ALPHA, slot_id: @slot.id,
                      on_duty: Time.current - 1.hour, additional_notes: "test")

    roster = AlphaShiftRoster.for_slot(@slot)

    assert_equal 1, roster.signed_in_count
    assert roster.any_signed_in?
    assert_equal ["ZedAlpha"], roster.signed_in.map { |entry| entry.person.callsign }
  end

  test "a closed timesheet does not count as signed in" do
    Timesheet.create!(person_id: @zed.id, position_id: Position::ALPHA, slot_id: @slot.id,
                      on_duty: Time.current - 3.hours, off_duty: Time.current - 1.hour,
                      additional_notes: "test")

    assert_equal 0, AlphaShiftRoster.for_slot(@slot).signed_in_count
  end

  test "a mentor rank of 3 or worse becomes a flag, a better rank does not" do
    PersonIntake.create!(person_id: @zed.id, year: YEAR, mentor_rank: Intake::BELOW_AVERAGE)
    PersonIntake.create!(person_id: @abe.id, year: YEAR, mentor_rank: Intake::ABOVE_AVERAGE)

    roster = AlphaShiftRoster.for_slot(@slot)
    flagged = roster.entries.find { |entry| entry.person == @zed }
    clean = roster.entries.find { |entry| entry.person == @abe }

    assert flagged.flagged?
    assert_equal [[YEAR, Intake::BELOW_AVERAGE]],
                 flagged.flags.map { |flag| [flag[:year], flag[:rank]] }
    assert_not clean.flagged?
    # The better-ranked year is still part of the team history the information
    # sheet prints -- it just isn't a flag.
    assert_equal [[YEAR, Intake::ABOVE_AVERAGE]],
                 clean.mentor_team.map { |team_year| [team_year[:year], team_year[:rank]] }
    assert_equal 1, roster.flagged_count
  end

  test "ranks recorded after the shift's year do not reach its roster" do
    PersonIntake.create!(person_id: @zed.id, year: YEAR + 1, mentor_rank: Intake::FLAG)

    roster = AlphaShiftRoster.for_slot(@slot)

    assert_not roster.entries.find { |entry| entry.person == @zed }.flagged?
  end

  test "mentor history is gathered per year with its mentors" do
    mentor = create_person("HistMentor")
    PersonMentor.create!(person: @zed, mentor: mentor, mentor_year: 2024,
                         status: PersonMentor::STATUS_BONK)

    entry = AlphaShiftRoster.for_slot(@slot).entries.find { |e| e.person == @zed }

    assert_equal [{ year: 2024, status: PersonMentor::STATUS_BONK, mentors: ["HistMentor"] }],
                 entry.mentor_years
  end

  test "mentor status comes from the shift's own year and defaults to pending" do
    mentor = create_person("StatusMentor")
    PersonMentor.create!(person: @zed, mentor: mentor, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)
    PersonMentor.create!(person: @abe, mentor: mentor, mentor_year: YEAR - 1,
                         status: PersonMentor::STATUS_BONK)

    roster = AlphaShiftRoster.for_slot(@slot)
    passed = roster.entries.find { |entry| entry.person == @zed }
    # A bonk in an EARLIER year says nothing about this shift, so this year
    # reads pending -- and pending is not bonked.
    other = roster.entries.find { |entry| entry.person == @abe }

    assert_equal PersonMentor::STATUS_PASS, passed.mentor_status
    assert_not passed.bonked?
    assert_equal PersonMentor::STATUS_PENDING, other.mentor_status
    assert_not other.bonked?
  end

  test "a bonk in the shift's year marks the entry bonked" do
    mentor = create_person("BonkMentor")
    PersonMentor.create!(person: @zed, mentor: mentor, mentor_year: YEAR,
                         status: PersonMentor::STATUS_BONK)

    entry = AlphaShiftRoster.for_slot(@slot).entries.find { |e| e.person == @zed }

    assert entry.bonked?
  end
end
