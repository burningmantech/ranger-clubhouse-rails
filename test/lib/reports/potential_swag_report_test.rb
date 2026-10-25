# frozen_string_literal: true

require "test_helper"

class PotentialSwagReportTest < ActiveSupport::TestCase
  YEAR = 2026

  setup do
    Current.reset

    # The report reads every Person, so the fixtures are cleared and only the
    # subjects given service. Both columns are set directly: creating Timesheet
    # rows would fire YearsManagement, which recomputes them and applies the
    # six-hour rule that would silently drop these years. years_as_ranger is
    # nullable; years_of_signups is NOT NULL, so it is cleared to an empty array
    # rather than to nil.
    Person.update_all(years_as_ranger: nil, years_of_signups: [])

    @candidate = person(:active_ranger)   # 4 years -> 5-year candidate
    @veteran = person(:plate_collision_ranger) # 9 years -> 10-year candidate
    @between = person(:ranger_with_custom_gender) # 2 years -> no milestone
    @retired = person(:retired_ranger)    # 14 years -> 15-year candidate
    @newcomer = person(:inactive_ranger)  # no service at all

    @candidate.update!(years_as_ranger: [2022, 2023, 2024, 2025])
    @veteran.update!(years_as_ranger: (2017..2025).to_a)
    @between.update!(years_as_ranger: [2024, 2025])
    @retired.update!(years_as_ranger: (2010..2023).to_a)
  end

  teardown { Current.reset }

  def rows_by_callsign
    PotentialSwagReport.execute(YEAR).index_by(&:callsign)
  end

  test "lists only the active statuses, in case-insensitive callsign order" do
    rows = PotentialSwagReport.execute(YEAR)

    assert_equal rows.map { |row| row.callsign.downcase }.sort,
                 rows.map { |row| row.callsign.downcase }
    assert(rows.all? { |row| Person::ACTIVE_STATUSES.include?(row.status) })
    assert_not_includes rows.map(&:callsign), person(:prospective_ranger).callsign
  end

  # The whole point of the report: years + 1 landing on a five-year mark.
  test "the milestone is the coming event, not the years already rangered" do
    rows = rows_by_callsign

    assert_equal 5, rows[@candidate.callsign].milestone
    assert_equal "5-year service", rows[@candidate.callsign].service_label
    assert_equal 10, rows[@veteran.callsign].milestone
    assert_equal 15, rows[@retired.callsign].milestone

    assert_nil rows[@between.callsign].milestone
    assert_nil rows[@between.callsign].service_label
  end

  test "milestone_for covers the boundaries" do
    assert_nil PotentialSwagReport.milestone_for(0), "a new account is not a 1-year candidate"
    assert_nil PotentialSwagReport.milestone_for(3)
    assert_equal 5, PotentialSwagReport.milestone_for(4)
    assert_nil PotentialSwagReport.milestone_for(5)
    assert_equal 25, PotentialSwagReport.milestone_for(24)
  end

  # Kept, unlike EventsRangeredReport: this roster is scoped by status, and
  # someone at zero years is an active account who will reach a mark later.
  test "people with no service are listed with no years to show" do
    row = rows_by_callsign[@newcomer.callsign]

    assert_not_nil row, "an active-status account with no service still belongs on the roster"
    assert_equal 0, row.years
    assert_nil row.first_year
    assert_nil row.last_year
    assert_nil row.milestone
  end

  test "first and last year come from the same list the count does" do
    row = rows_by_callsign[@veteran.callsign]

    assert_equal 9, row.years
    assert_equal 2017, row.first_year
    assert_equal 2025, row.last_year
  end

  # json_valid() admits scalars and objects, and the upstream Laravel app writes
  # this column too, so a malformed row must not take the report down.
  #
  # The values are written as real Ruby objects: years_as_ranger is
  # serialize ..., coder: JSON, so update_all runs whatever it is given back
  # through the coder -- handing it the String '{"oops":1}' stores a JSON
  # string literal and tests the wrong branch entirely.
  test "a malformed years_as_ranger is treated as no service, not raised" do
    [{ "oops" => 1 }, "nonsense", 42].each do |garbage|
      Person.where(id: @candidate.id).update_all(years_as_ranger: garbage)

      row = rows_by_callsign[@candidate.callsign]
      assert_equal 0, row.years, garbage.inspect
      assert_nil row.milestone, garbage.inspect
    end
  end

  # An array is not enough: min/max raise on anything they cannot compare, and
  # that would 500 the page and the CSV for every reader.
  test "entries that are not years are dropped rather than compared" do
    Person.where(id: @candidate.id).update_all(years_as_ranger: [nil, 2020])

    row = rows_by_callsign[@candidate.callsign]
    assert_equal 1, row.years
    assert_equal 2020, row.first_year
    assert_equal 2020, row.last_year

    Person.where(id: @candidate.id).update_all(years_as_ranger: [2019, "2020", nil])
    row = rows_by_callsign[@candidate.callsign]
    assert_equal 1, row.years
    assert_equal 2019, row.first_year, "a String year must not reach the column"
    assert_equal 2019, row.last_year

    Person.where(id: @candidate.id).update_all(years_as_ranger: ["2019", "2020"])
    assert_equal 0, rows_by_callsign[@candidate.callsign].years
  end

  test "bookkeeping callsigns are dropped" do
    ["ROC Monitor 1", "testing thing", "lam #4", "temp 12", "Somebody (test)"].each do |callsign|
      @between.update_columns(callsign:)

      assert_not_includes PotentialSwagReport.execute(YEAR).map(&:callsign), callsign
    end

    # The exclusion is anchored, so a real callsign that merely contains one of
    # the words survives.
    @between.update_columns(callsign: "Contesting")
    assert_includes PotentialSwagReport.execute(YEAR).map(&:callsign), "Contesting"
  end

  # The divergence guard: years_of_signups cannot back this column because it
  # counts trainings, and this one deliberately does not.
  test "a training sign-up is not a sign-up" do
    sign_up(@candidate, training_position)
    sign_up(@veteran, positions(:ood_position))

    rows = rows_by_callsign
    assert_not rows[@candidate.callsign].signed_up,
               "signing up for a Training is not turning out to ranger"
    assert rows[@veteran.callsign].signed_up
  end

  # position.type is nullable, and upstream's `type != 'Training'` drops a NULL
  # row rather than keeping it -- SQL says unknown, not true.
  test "a sign-up for a position with no type still counts" do
    assert_nil positions(:ood_position).type, "fixture guard: this position has no type"
    sign_up(@candidate, positions(:ood_position))

    assert rows_by_callsign[@candidate.callsign].signed_up
  end

  test "a sign-up in another year is not this year's" do
    sign_up(@candidate, positions(:ood_position), year: YEAR - 1)

    assert_not rows_by_callsign[@candidate.callsign].signed_up
  end

  test "milestones roll the roster up largest first and count what matches" do
    sign_up(@veteran, positions(:ood_position))

    rows = PotentialSwagReport.execute(YEAR)
    lines = PotentialSwagReport.milestones(rows)

    assert_equal [15, 10, 5], lines.map { |line| line[:milestone] }
    assert_equal [1, 1, 1], lines.map { |line| line[:people] }
    assert_equal [0, 1, 0], lines.map { |line| line[:signed_up] }
    assert_equal [1, 1, 1], lines.map { |line| line[:matching] },
                 "without a predicate, matching is just people"

    matching = PotentialSwagReport.milestones(rows, &:signed_up)
    assert_equal [0, 1, 0], matching.map { |line| line[:matching] }
    assert_equal [15, 10, 5], matching.map { |line| line[:milestone] },
                 "a line that can deliver no one is still offered"
  end

  private

  def training_position
    @training_position ||= Position.create!(title: "Test Training",
                                            type: Position::TYPE_TRAINING,
                                            active: true)
  end

  def sign_up(person, position, year: YEAR)
    slot = Slot.create!(position:, max: 10, active: true,
                        begins: Time.zone.local(year, 8, 20, 9, 0, 0),
                        ends: Time.zone.local(year, 8, 20, 17, 0, 0))
    PersonSlot.create!(person:, slot:)
  end
end
