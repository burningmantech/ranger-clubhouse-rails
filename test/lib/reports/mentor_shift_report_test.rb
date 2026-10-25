# frozen_string_literal: true

require "test_helper"

class MentorShiftReportTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  # Clear of the 2025/2026 fixture data.
  YEAR = 2031

  setup do
    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha")
    @mentor_position = Position.create!(id: Position::MENTOR, title: "Mentor")
    @alpha_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 7, 0, 0),
                              ends: Time.zone.local(YEAR, 8, 26, 13, 0, 0), description: "Alpha shift")
  end

  def entries_for(report, group_key)
    group = report.groups.find { |candidate| candidate.key == group_key }
    group.positions.flat_map { |position| position.slots.flat_map(&:entries) }
  end

  test "the window includes both endpoints and nothing beyond them" do
    on_early_edge = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 6, 0, 0),
                                ends: Time.zone.local(YEAR, 8, 26, 12, 0, 0))
    on_late_edge = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 10, 0, 0),
                               ends: Time.zone.local(YEAR, 8, 26, 16, 0, 0))
    past_early_edge = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 5, 59, 0),
                                  ends: Time.zone.local(YEAR, 8, 26, 11, 59, 0))
    past_late_edge = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 10, 1, 0),
                                 ends: Time.zone.local(YEAR, 8, 26, 16, 1, 0))

    report = MentorShiftReport.for_slot(@alpha_slot)

    window_slot_ids = report.groups.flat_map { |group| group.positions.flat_map { |position| position.slots.map { |slot_sign_ups| slot_sign_ups.slot.id } } }
    assert_includes window_slot_ids, on_early_edge.id
    assert_includes window_slot_ids, on_late_edge.id
    assert_not_includes window_slot_ids, past_early_edge.id
    assert_not_includes window_slot_ids, past_late_edge.id
  end

  test "a position whose row was deleted still renders a placeholder title" do
    # belongs_to demands the row at creation, so delete it afterwards.
    khaki_position = Position.create!(id: Position::MENTOR_KHAKI, title: "Mentor Khaki")
    khaki_slot = create_slot(khaki_position, begins: Time.zone.local(YEAR, 8, 26, 7, 0, 0),
                             ends: Time.zone.local(YEAR, 8, 26, 13, 0, 0))
    Position.delete(khaki_position.id)

    report = MentorShiftReport.for_slot(@alpha_slot)

    operations = report.groups.find { |group| group.key == :operations }
    khaki = operations.positions.find { |position| position.slots.any? { |slot_sign_ups| slot_sign_ups.slot.id == khaki_slot.id } }
    assert_equal "Position ##{Position::MENTOR_KHAKI}", khaki.title
  end

  test "unfilled counts empty shifts while group counts tally people" do
    mentor_slot = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 7, 0, 0),
                              ends: Time.zone.local(YEAR, 8, 26, 13, 0, 0))
    mentor = create_person("WindowMentor")
    PersonSlot.create!(person_id: mentor.id, slot_id: mentor_slot.id)

    report = MentorShiftReport.for_slot(@alpha_slot)

    # The Alpha shift itself has no sign-ups, so it is the one unfilled shift.
    assert_equal 1, report.unfilled_count
    assert_equal({ alphas: 0, mentors: 1, cheetahs: 0, operations: 0 }, report.group_counts)
    assert_empty entries_for(report, :alphas)
  end

  test "two bonk rows in the same year collapse to one badge year" do
    alpha = create_person("DoubleBonk")
    PersonSlot.create!(person_id: alpha.id, slot_id: @alpha_slot.id)
    mentor_one = create_person("MentorOne")
    mentor_two = create_person("MentorTwo")
    PersonMentor.create!(person: alpha, mentor: mentor_one, mentor_year: 2029,
                         status: PersonMentor::STATUS_BONK)
    PersonMentor.create!(person: alpha, mentor: mentor_two, mentor_year: 2029,
                         status: PersonMentor::STATUS_BONK)
    PersonMentor.create!(person: alpha, mentor: mentor_one, mentor_year: 2030,
                         status: PersonMentor::STATUS_PASS)

    report = MentorShiftReport.for_slot(@alpha_slot)

    assert_equal [[2029]], entries_for(report, :alphas).map(&:bonk_years)
  end

  test "on duty reads open current-year timesheets only" do
    travel_to Time.zone.local(YEAR, 8, 26, 12, 0, 0) do
      on_now = create_person("OpenShift")
      Timesheet.create!(person: on_now, position_id: Position::MENTOR,
                        on_duty: Time.zone.local(YEAR, 8, 26, 9, 0, 0), additional_notes: "test shift")
      closed = create_person("ClosedShift")
      Timesheet.create!(person: closed, position_id: Position::MENTOR,
                        on_duty: Time.zone.local(YEAR, 8, 26, 2, 0, 0),
                        off_duty: Time.zone.local(YEAR, 8, 26, 8, 0, 0), additional_notes: "test shift")
      prior_year = create_person("PriorYear")
      Timesheet.create!(person: prior_year, position_id: Position::MENTOR,
                        on_duty: Time.zone.local(YEAR - 1, 8, 26, 9, 0, 0), additional_notes: "test shift")

      report = MentorShiftReport.on_duty

      entries = entries_for(report, :mentors)
      assert_equal [on_now.callsign], entries.map { |entry| entry.person.callsign }
      # Elapsed to the frozen noon.
      assert_equal 3.hours.to_i, entries.first.duration
      assert report.on_duty?
    end
  end
end
