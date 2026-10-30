# frozen_string_literal: true

require "test_helper"

# Status Change Recommendations, the report half: who lands in each of the five
# groups, where each rule's year boundary sits, and the three decorated columns.
class RecommendStatusChangeReportTest < ActiveSupport::TestCase
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  INACTIVE_CUTOFF = 2024 # the first of the last three events
  RETIRED_CUTOFF = 2022  # the first of the last five

  setup do
    travel_to Time.zone.local(YEAR, 10, 1, 12, 0, 0)
    Current.reset

    # The report reads every Person, so the fixtures are parked in a status no
    # group proposes and their shifts cleared. What each test creates is then
    # the only thing left for the report to find.
    Timesheet.delete_all
    Person.update_all(status: Person::AUDITOR, vintage: false, years_as_ranger: nil)

    @dirt = Position.create!(id: Position::DIRT, title: "Dirt",
                             type: Position::TYPE_FRONTLINE, active: true)
    @alpha = Position.create!(id: Position::ALPHA, title: "Alpha",
                              type: Position::TYPE_FRONTLINE, active: true)
    @training = Position.create!(id: Position::TRAINING, title: "In-Person Training",
                                 type: Position::TYPE_TRAINING, active: true)
  end

  teardown { travel_back }

  # --- Inactive -------------------------------------------------------------

  test "an active Ranger away for three events but not five is proposed inactive" do
    person = create_person("Bandsaw")
    ranger(person, RETIRED_CUTOFF)

    assert_equal [person.id], group_ids(RecommendStatusChangeReport::INACTIVE)
  end

  test "a shift in the cutoff year itself keeps a Ranger off the inactive list" do
    person = create_person("Halyard")
    ranger(person, RETIRED_CUTOFF)
    ranger(person, INACTIVE_CUTOFF)

    assert_empty group_ids(RecommendStatusChangeReport::INACTIVE)
  end

  test "the year before the cutoff still proposes inactive" do
    person = create_person("Slipstream")
    ranger(person, INACTIVE_CUTOFF - 1)

    assert_equal [person.id], group_ids(RecommendStatusChangeReport::INACTIVE)
  end

  test "a training entry alone keeps a Ranger off the inactive list" do
    person = create_person("Chalkline")
    ranger(person, RETIRED_CUTOFF)
    ranger(person, INACTIVE_CUTOFF, position: @training)

    assert_empty group_ids(RecommendStatusChangeReport::INACTIVE)
  end

  test "a Ranger away longer than five events is proposed retired, not inactive" do
    person = create_person("Aloe")
    ranger(person, RETIRED_CUTOFF - 1)

    assert_empty group_ids(RecommendStatusChangeReport::INACTIVE)
    assert_equal [person.id], group_ids(RecommendStatusChangeReport::RETIRED)
  end

  # --- Retired --------------------------------------------------------------

  test "inactive and inactive-extension accounts join the retired list" do
    away = [create_person("Pinwheel", status: Person::INACTIVE),
            create_person("Kettle", status: Person::INACTIVE_EXTENSION)]
    away.each { |person| ranger(person, RETIRED_CUTOFF - 2) }

    assert_equal away.map(&:id).sort, group_ids(RecommendStatusChangeReport::RETIRED).sort
  end

  test "a training entry does not save a Ranger from the retired list" do
    person = create_person("Deepwater")
    ranger(person, RETIRED_CUTOFF - 1)
    ranger(person, YEAR, position: @training)

    assert_equal [person.id], group_ids(RecommendStatusChangeReport::RETIRED)
  end

  # --- Active ---------------------------------------------------------------

  test "an inactive or retired Ranger who came back is proposed active" do
    back = [create_person("Marmalade", status: Person::RETIRED),
            create_person("TwoStep", status: Person::INACTIVE)]
    back.each { |person| ranger(person, INACTIVE_CUTOFF) }

    assert_equal back.map(&:id).sort, group_ids(RecommendStatusChangeReport::ACTIVE).sort
  end

  test "a Ranger whose only recent entry is training is not proposed active" do
    person = create_person("Ledger", status: Person::INACTIVE)
    ranger(person, INACTIVE_CUTOFF, position: @training)

    assert_empty group_ids(RecommendStatusChangeReport::ACTIVE)
  end

  # --- Past prospective -----------------------------------------------------

  test "every leftover applicant is proposed past prospective" do
    leftover = [create_person("SmithJane26", status: Person::PROSPECTIVE),
                create_person("Zebra", status: Person::ALPHA),
                create_person("Mirage", status: Person::BONKED)]
    create_person("Steady")

    assert_equal leftover.map(&:id).sort,
                 group_ids(RecommendStatusChangeReport::PAST_PROSPECTIVE).sort
  end

  # --- Vintage --------------------------------------------------------------

  test "ten years of rangering earns a vintage proposal, nine does not" do
    earned = create_person("Lodestar", years: (2010..2019).to_a)
    create_person("Newer", years: (2011..2019).to_a)

    assert_equal [earned.id], group_ids(RecommendStatusChangeReport::VINTAGE)
  end

  test "a callsign already marked vintage is not proposed again" do
    person = create_person("Oldtimer", years: (2010..2019).to_a)
    person.update_columns(vintage: true)

    assert_empty group_ids(RecommendStatusChangeReport::VINTAGE)
  end

  # --- Test accounts --------------------------------------------------------

  test "bookkeeping and laminate accounts are never proposed" do
    ["ROC Monitor 1", "testing thing", "Lam #4", "Temp 12", "Bandsaw (test)"].each_with_index do |callsign, index|
      rename create_person("Placeholder#{index}", status: Person::PROSPECTIVE), callsign
    end
    real = create_person("SmithJane26", status: Person::PROSPECTIVE)

    assert_equal [real.id], group_ids(RecommendStatusChangeReport::PAST_PROSPECTIVE)
  end

  test "counts agree with the rows they describe" do
    ranger(create_person("Bandsaw"), RETIRED_CUTOFF)
    ranger(rename(create_person("Placeholder"), "ROC Monitor 1"), RETIRED_CUTOFF)

    counts = RecommendStatusChangeReport.counts(YEAR)

    assert_equal 1, counts[RecommendStatusChangeReport::INACTIVE]
    assert_equal 1, rows_for(RecommendStatusChangeReport::INACTIVE).size
  end

  # --- Decorated columns ----------------------------------------------------

  test "the row carries the last year rangered, years, and alpha year" do
    # The years column is the stored count, which is what every other Rangered
    # figure in the app reports. It is set here rather than left to the shift
    # rows below, because the code that keeps it current is stubbed out in the
    # test environment.
    person = create_person("FigNewton", years: [2019, RETIRED_CUTOFF])
    ranger(person, 2019, position: @alpha)
    ranger(person, RETIRED_CUTOFF)

    row = rows_for(RecommendStatusChangeReport::INACTIVE).sole

    assert_equal RETIRED_CUTOFF, row.last_year
    assert_equal 2, row.years
    assert_equal 2019, row.alpha_year
  end

  test "the earliest dirt year stands in for an alpha year never recorded" do
    person = create_person("Pinwheel")
    ranger(person, 2004)
    ranger(person, RETIRED_CUTOFF)

    assert_equal 2004, rows_for(RecommendStatusChangeReport::INACTIVE).sole.alpha_year
  end

  test "the most recent alpha entry is the alpha year" do
    person = create_person("Rewalked")
    ranger(person, 2016, position: @alpha)
    ranger(person, 2019, position: @alpha)
    ranger(person, RETIRED_CUTOFF)

    assert_equal 2019, rows_for(RecommendStatusChangeReport::INACTIVE).sole.alpha_year
  end

  test "last year rangered ignores entries that are not shifts" do
    person = create_person("Deepwater")
    ranger(person, RETIRED_CUTOFF - 1)
    ranger(person, YEAR, position: @training)

    row = rows_for(RecommendStatusChangeReport::RETIRED).sole

    assert_equal RETIRED_CUTOFF - 1, row.last_year
  end

  test "a years column that is not a list of years proposes no one for vintage" do
    person = create_person("Malformed")
    person.update_columns(years_as_ranger: { "a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5,
                                             "f" => 6, "g" => 7, "h" => 8, "i" => 9,
                                             "j" => 10 }.to_json)

    assert_empty group_ids(RecommendStatusChangeReport::VINTAGE)
    assert_equal 0, RecommendStatusChangeReport.counts(YEAR)[RecommendStatusChangeReport::VINTAGE]
  end

  # --- Period ---------------------------------------------------------------

  test "the next event period moves both cutoffs a year on" do
    person = create_person("Bandsaw")
    ranger(person, INACTIVE_CUTOFF)

    assert_empty group_ids(RecommendStatusChangeReport::INACTIVE)
    assert_equal [person.id], group_ids(RecommendStatusChangeReport::INACTIVE, year: YEAR + 1)
  end

  test "an unknown period reads as the current one" do
    assert_equal RecommendStatusChangeReport::PERIOD_NOW,
                 RecommendStatusChangeReport.known_period("last-decade")
    assert_equal YEAR, RecommendStatusChangeReport.year_for("last-decade")
    assert_equal YEAR + 1,
                 RecommendStatusChangeReport.year_for(RecommendStatusChangeReport::PERIOD_NEXT)
  end

  # --- Holding converted people on the page ---------------------------------

  test "keep_ids holds a person whose change has already landed" do
    person = create_person("Bandsaw")
    ranger(person, RETIRED_CUTOFF)
    person.update_columns(status: Person::INACTIVE)

    assert_empty group_ids(RecommendStatusChangeReport::INACTIVE)
    assert_equal [person.id],
                 rows_for(RecommendStatusChangeReport::INACTIVE, keep_ids: [person.id]).map(&:id)
  end

  # --- Group shape ----------------------------------------------------------

  test "each group knows which columns and which write it carries" do
    inactive = RecommendStatusChangeReport.find_group(RecommendStatusChangeReport::INACTIVE)
    applicants = RecommendStatusChangeReport.find_group(RecommendStatusChangeReport::PAST_PROSPECTIVE)
    vintage = RecommendStatusChangeReport.find_group(RecommendStatusChangeReport::VINTAGE)

    assert_predicate inactive, :sets_status?
    assert_predicate inactive, :shows_history?
    assert_predicate inactive, :shows_vintage?
    assert_equal Person::INACTIVE, inactive.target_status

    assert_not applicants.shows_history?
    assert_not applicants.shows_vintage?

    assert_not vintage.sets_status?
    assert_nil vintage.target_status
    assert_equal BulkUpload::PersonFlagHandler, vintage.action.handler
  end

  test "an unknown group key finds nothing" do
    assert_nil RecommendStatusChangeReport.find_group("shiny-pennies")
  end

  private

  # create_person builds the email address out of the callsign, and these
  # callsigns are not the shape an address takes, so the name is set after.
  def rename(person, callsign)
    person.update_columns(callsign:, callsign_normalized: WordUtils.normalize_word(callsign))
    person
  end

  def ranger(person, year, position: @dirt)
    on_duty = Time.zone.local(year, 8, 28, 18, 0, 0)
    Timesheet.create!(person:, position:, on_duty:, off_duty: on_duty + 6.hours,
                      additional_notes: "test shift")
  end

  def rows_for(key, year: YEAR, keep_ids: [])
    RecommendStatusChangeReport.rows(RecommendStatusChangeReport.find_group(key), year, keep_ids:)
  end

  def group_ids(key, year: YEAR) = rows_for(key, year:).map(&:id)
end
