# frozen_string_literal: true

require "test_helper"

class RetentionReportTest < ActiveSupport::TestCase
  include PersonTestFactory

  # A year the window certainly covers, and one it certainly does not.
  IN_WINDOW = Current.year - 1
  BEFORE_WINDOW = Current.year - 9

  setup do
    Current.reset
    @ood = positions(:ood_position)
    @alpha = ensure_position(Position::ALPHA, "Alpha")
    @training = ensure_position(Position::TRAINING, "Training")
    @deep_freeze = ensure_position(Position::DEEP_FREEZE, "Deep Freeze")
  end

  teardown { Current.reset }

  test "the window is five events, most recent last" do
    assert_equal [2022, 2023, 2024, 2025, 2026], RetentionReport.years(2026)
  end

  # No event was held in 2020 or 2021, so neither counts as one of the five.
  test "the window skips the years with no event" do
    assert_equal [2019, 2022, 2023, 2024, 2025], RetentionReport.years(2025)
    assert_equal [2015, 2016, 2017, 2018, 2019], RetentionReport.years(2021)
  end

  test "a Ranger who rangered inside the window is listed" do
    person = rangering_person("WindowRanger", years: [IN_WINDOW])

    assert_includes callsigns, person.callsign
  end

  test "shifts that do not count as rangering leave a Ranger out" do
    alpha = create_person("AlphaOnly", years: [IN_WINDOW])
    shift(alpha, position: @alpha)
    training = create_person("TrainingOnly", years: [IN_WINDOW])
    shift(training, position: @training)
    deep_freeze = create_person("FreezeOnly", years: [IN_WINDOW])
    shift(deep_freeze, position: @deep_freeze)
    echelon = create_person("EchelonOnly", years: [IN_WINDOW])
    shift(echelon, is_echelon: true)

    listed = callsigns
    [alpha, training, deep_freeze, echelon].each do |person|
      assert_not_includes listed, person.callsign
    end
  end

  test "a Ranger whose last shift is older than the window is left out" do
    person = create_person("LongGone", years: [BEFORE_WINDOW])
    shift(person, year: BEFORE_WINDOW)

    assert_not_includes callsigns, person.callsign
  end

  test "only the four roster statuses are asked to take the survey" do
    listed = [Person::ACTIVE, Person::INACTIVE, Person::INACTIVE_EXTENSION, Person::RETIRED]
      .map { |status| rangering_person("Roster#{status.delete(" ").titleize}", status:) }
    left_out = [Person::ALPHA, Person::PROSPECTIVE, Person::DECEASED, Person::DISMISSED]
      .map { |status| rangering_person("Off#{status.delete(" ").titleize}", status:) }

    found = callsigns
    listed.each { |person| assert_includes found, person.callsign }
    left_out.each { |person| assert_not_includes found, person.callsign }
  end

  test "the year columns come from the years the Clubhouse credits" do
    person = rangering_person("Veteran", years: [2015, 2019, IN_WINDOW])
    row = row_for(person)

    assert_equal 2015, row.first_year
    assert_equal IN_WINDOW, row.last_year
    assert_equal 3, row.total_years
    assert row.rangered?(2019)
    assert_not row.rangered?(2018)
  end

  # A shift can put someone in the report without earning them the year -- six
  # hours are needed from 2025 on. They are still listed, with nothing in the
  # year columns.
  test "a Ranger with no credited year is listed with no years" do
    person = rangering_person("ShortShift", years: [])
    row = row_for(person)

    assert_nil row.first_year
    assert_nil row.last_year
    assert_equal 0, row.total_years
  end

  # Keyed by what the page filters and counts on -- a count keyed by anything
  # else would still add up, and would break the select and every stat box.
  test "the counts are keyed by status and by the last year rangered" do
    retired = rangering_person("CountsRetired", status: Person::RETIRED, years: [IN_WINDOW])
    veteran = rangering_person("CountsVeteran", years: [2015, IN_WINDOW])
    report = RetentionReport.execute

    assert_equal 1, report.status_counts.fetch(Person::RETIRED)
    assert_equal report.rows.size, report.status_counts.values.sum

    assert_operator report.counts_by_last_year.fetch(IN_WINDOW.to_s), :>=, 2
    assert_equal report.rows.size, report.counts_by_last_year.values.sum
    assert_equal [retired.callsign, veteran.callsign].sort,
                 report.rows.select { |row| row.last_year_key == IN_WINDOW.to_s }
                       .map(&:callsign).sort
  end

  # A Ranger with no credited year has no year to be counted under, and the
  # filter still has to be able to name them.
  test "a Ranger with no credited year counts under the no-years key" do
    person = rangering_person("NoCredit", years: [])

    assert_equal RetentionReport::NO_YEARS,
                 RetentionReport.execute.rows.find { |row| row.callsign == person.callsign }.last_year_key
  end

  # A shift after the window belongs to an event this report is not about.
  test "a shift after the window does not list anybody" do
    person = create_person("Latecomer", years: [])
    shift(person, year: Current.year + 1)

    assert_not_includes RetentionReport.execute(end_year: Current.year - 1).rows.map(&:callsign),
                        person.callsign
  end

  # The column is JSON written by another app too, and its check constraint
  # admits a list holding anything.
  test "a year list holding junk counts only the years in it" do
    person = rangering_person("MixedYears", years: [])
    # The Array, not its JSON text: update_columns runs the value through the
    # column's coder, so a string would be stored double-encoded.
    person.update_columns(years_as_ranger: [nil, 2015, "2019", IN_WINDOW])
    row = row_for(person)

    assert_equal 2015, row.first_year
    assert_equal IN_WINDOW, row.last_year
    assert_equal 2, row.total_years
  end

  # Case-insensitively: the column's collation is, so a byte-order sort would
  # call a correctly ordered roster wrong.
  test "rows come back by callsign" do
    callsigns = RetentionReport.execute.rows.map(&:callsign)

    assert_equal callsigns.sort_by(&:downcase), callsigns
  end

  private

  def callsigns = RetentionReport.execute.rows.map(&:callsign)

  def row_for(person) = RetentionReport.execute.rows.find { |row| row.callsign == person.callsign }

  # Someone in the report: a shift that counts, inside the window.
  def rangering_person(callsign, status: Person::ACTIVE, years: [IN_WINDOW])
    person = create_person(callsign, status:, years:)
    shift(person)
    person
  end

  def shift(person, position: @ood, year: IN_WINDOW, is_echelon: false)
    Timesheet.create!(person:, position:, is_echelon:,
                      on_duty: Time.local(year, 8, 28, 10, 0, 0),
                      off_duty: Time.local(year, 8, 28, 18, 0, 0),
                      additional_notes: "test shift")
  end

  # The report names Alpha, Training, and Deep Freeze by id, and the fixtures
  # carry none of them.
  def ensure_position(id, title)
    position = Position.find_or_initialize_by(id:)
    position.title = title
    position.save!
    position
  end
end
