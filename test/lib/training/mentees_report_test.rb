# frozen_string_literal: true

require "test_helper"

# Training::MenteesReport: who the roster is built from, the grant matrix, the
# grant/last-rangered years, and the trainings that have no report at all.
class Training::MenteesReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)

    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true)
    # Titled so the report's alphabetical ordering is observable: Sanctuary
    # sorts first even though it is second in ART_GRADUATE_TO_POSITIONS.
    @mentee = Position.create!(id: Position::GREEN_DOT_MENTEE, title: "Green Dot Mentee",
                               type: "Frontline", active: true)
    @sanctuary = Position.create!(id: Position::SANCTUARY_MENTEE, title: "Anctuary Mentee",
                                  type: "Frontline", active: true)

    @alpha = person(:active_ranger)
    @beta = person(:inactive_ranger)
  end

  teardown { travel_back }

  def grant(person_record, position, joined_on: nil, left_on: nil)
    PersonPosition.create!(person_id: person_record.id, position_id: position.id)
    return unless joined_on

    PersonPositionLog.create!(person_id: person_record.id, position_id: position.id,
                              joined_on:, left_on:)
  end

  def rangered(person_record, position, on_duty)
    Timesheet.create!(person_id: person_record.id, position_id: position.id,
                      on_duty:, off_duty: on_duty + 4.hours, additional_notes: "test")
  end

  def report = Training::MenteesReport.execute(@green_dot)

  test "a training with no mentee positions has no report" do
    sandman = Position.create!(id: Position::SANDMAN_TRAINING, title: "Sandman Training",
                               type: Position::TYPE_TRAINING, active: true)
    result = Training::MenteesReport.execute(sandman)

    assert_empty result.positions
    assert_empty result.people
  end

  test "the roster is empty when no one holds a mentee position" do
    assert_empty report.people
  end

  test "positions are the ART's mentee positions ordered by title" do
    grant(@alpha, @mentee)

    assert_equal ["Anctuary Mentee", "Green Dot Mentee"], report.positions.map(&:title)
  end

  test "only people holding a mentee position are listed, by callsign" do
    grant(@beta, @mentee)
    grant(@alpha, @sanctuary)
    person(:retired_ranger) # holds nothing

    callsigns = report.people.map(&:callsign)

    assert_equal 2, callsigns.size
    assert_equal callsigns.sort, callsigns
    assert_includes callsigns, @alpha.callsign
    assert_includes callsigns, @beta.callsign
  end

  test "a position the person does not hold reads as not granted" do
    grant(@alpha, @mentee)

    grants = report.people.first.grants.index_by { |g| g.position.id }

    assert_predicate grants[Position::GREEN_DOT_MENTEE], :granted?
    assert_not_predicate grants[Position::SANCTUARY_MENTEE], :granted?
  end

  test "the grant year comes from the open log row" do
    grant(@alpha, @mentee, joined_on: Time.zone.local(2024, 3, 1))

    assert_equal 2024, report.people.first.grants.find { |g| g.position.id == @mentee.id }.granted_year
  end

  test "a closed log row does not supply a grant year" do
    grant(@alpha, @mentee, joined_on: Time.zone.local(2024, 3, 1), left_on: Time.zone.local(2025, 3, 1))

    assert_nil report.people.first.grants.find { |g| g.position.id == @mentee.id }.granted_year
  end

  test "with several open log rows the earliest year wins" do
    grant(@alpha, @mentee, joined_on: Time.zone.local(2025, 3, 1))
    PersonPositionLog.create!(person_id: @alpha.id, position_id: @mentee.id,
                              joined_on: Time.zone.local(2023, 3, 1))

    assert_equal 2023, report.people.first.grants.find { |g| g.position.id == @mentee.id }.granted_year
  end

  test "a grant with no log row has an unknown year" do
    grant(@alpha, @mentee)

    assert_nil report.people.first.grants.find { |g| g.position.id == @mentee.id }.granted_year
  end

  test "last rangered is the most recent timesheet year for that position" do
    grant(@alpha, @mentee)
    rangered(@alpha, @mentee, Time.zone.local(2022, 8, 30, 18, 0, 0))
    rangered(@alpha, @mentee, Time.zone.local(2025, 8, 30, 18, 0, 0))

    assert_equal 2025, report.people.first.grants.find { |g| g.position.id == @mentee.id }.last_rangered_year
  end

  test "a timesheet in another position does not count" do
    grant(@alpha, @mentee)
    rangered(@alpha, @sanctuary, Time.zone.local(2025, 8, 30, 18, 0, 0))

    grants = report.people.first.grants.index_by { |g| g.position.id }

    assert_nil grants[Position::GREEN_DOT_MENTEE].last_rangered_year
    assert_equal 2025, grants[Position::SANCTUARY_MENTEE].last_rangered_year
  end

  test "never rangered means none of the held positions was ever rangered" do
    grant(@alpha, @mentee)
    grant(@alpha, @sanctuary)
    rangered(@alpha, @sanctuary, Time.zone.local(2025, 8, 30, 18, 0, 0))
    grant(@beta, @mentee)

    people = report.people.index_by(&:callsign)

    assert_not_predicate people[@alpha.callsign], :never_rangered?
    assert_equal 2025, people[@alpha.callsign].last_rangered_year
    assert_predicate people[@beta.callsign], :never_rangered?
    assert_nil people[@beta.callsign].last_rangered_year
  end
end
