# frozen_string_literal: true

require "test_helper"

class People::RetentionReportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include PersonTestFactory
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper     # assert_report_card / card_answer / assert_no_card_question
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @vc = person(:plate_collision_ranger)
    @outsider = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "VC")
    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)

    @ood = positions(:ood_position)
    @years = RetentionReport.years(Current.year)

    # The report reads every Person, so the fixtures are cleared and only the
    # subjects are given shifts and years. The shifts decide who is listed; the
    # years are set directly, because YearsManagement does not run in tests and
    # creating a timesheet therefore recomputes nothing.
    Timesheet.delete_all
    Person.update_all(years_as_ranger: nil)

    @regular = rangering_person("Regular", years: @years)
    @lapsed = rangering_person("Lapsed", years: @years.first(2))
    @retired = rangering_person("Rested", status: Person::RETIRED, years: [@years.last])

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "admin and VC may read the report" do
    [@admin, @vc].each do |reader|
      sign_in_as(reader)
      get people_retention_report_path

      assert_response :success, "#{reader.callsign} should be allowed in"
    end
  end

  test "denies access without the admin or VC role" do
    sign_in_as(@outsider)
    get people_retention_report_path

    assert_response :redirect
  end

  test "lists everyone who rangered one of the last five events" do
    get people_retention_report_path

    assert_response :success
    [@regular, @lapsed, @retired].each { |person| assert_includes roster_callsigns, person.callsign }
  end

  # The card sits under the stat row, which only a report with someone on it
  # has. With no one to survey, the empty state says so on its own.
  test "the card explains the report where there is a roster to read" do
    get people_retention_report_path

    assert_report_card
    assert_match(/any of the last five events/, card_answer("Who is listed?"))

    Timesheet.delete_all
    get people_retention_report_path

    assert_match "there is no one to survey", response.body
    assert_report_card count: 0
  end

  # Five events through 2025 are 2019 and 2022 to 2025, so the year columns
  # jump. Through this year they run end to end, and a training server's clock
  # is the one still set where they do not.
  test "the card explains the missing years only when the five events reach over them" do
    question = "Why are 2020 and 2021 missing?"

    travel_to Time.zone.local(2025, 10, 1, 12, 0, 0) do
      @years = RetentionReport.years(Current.year)
      rangering_person("Backdated", years: @years)
      get people_retention_report_path

      assert_match(/no event in 2020 or 2021/, card_answer(question))
    end

    get people_retention_report_path

    assert_report_card
    assert_no_card_question question
  end

  test "each filter narrows the roster" do
    [[{ status: Person::RETIRED }, [@retired]],
     [{ last_year: @years.first(2).last.to_s }, [@lapsed]],
     [{ last_year: @years.last.to_s }, [@regular, @retired]],
     [{ status: Person::ACTIVE, last_year: @years.last.to_s }, [@regular]]].each do |filters, expected|
      get people_retention_report_path(**filters)

      assert_response :success
      assert_equal expected.map(&:callsign).sort, roster_callsigns.sort, filters.inspect
    end
  end

  # A stale link, or a typo, would otherwise render an empty roster with no way
  # to tell it from a real gap.
  test "a filter value the report does not hold is dropped, not applied" do
    get people_retention_report_path(status: Person::DECEASED, last_year: "1999")

    assert_response :success
    assert_equal 3, roster_callsigns.size
    assert_select "a[aria-label^=?]", "Remove filter: Status", count: 0
    assert_select "a[aria-label^=?]", "Remove filter: Last Rangered", count: 0
  end

  test "the counts describe the whole report" do
    get people_retention_report_path

    assert_match(/3\s*Rangers in the report/, stats_text)
    assert_match(/2\s*Rangered #{@years.last}/, stats_text)
    assert_match(/1\s*Last rangered earlier/, stats_text)
  end

  # Each filter alone can only offer values the report holds, so an empty
  # roster takes two of them disagreeing: the retired Ranger's last year is not
  # the one asked for.
  test "says so plainly when the filters match no one" do
    get people_retention_report_path(status: Person::RETIRED, last_year: @years.first(2).last.to_s)

    assert_response :success
    assert_empty roster_callsigns
    assert_match "No one matched the current filters", response.body
  end

  test "CSV carries upstream's columns and the year in its name" do
    get people_retention_report_path(format: :csv)

    assert_response :success
    assert_match "retention-report-#{@years.last}.csv", response.headers["Content-Disposition"]

    rows = response.body.split("\n")
    assert_equal People::RetentionReportController::CSV_HEADER.join(","), rows.first
    assert_equal 4, rows.size, "header plus the three Rangers"

    row = rows.find { |line| line.start_with?("#{@regular.callsign},") }
    assert_equal [@regular.callsign, "#{@regular.first_name} #{@regular.last_name}",
                  @regular.status, @regular.email,
                  @years.first.to_s, @years.last.to_s, @years.size.to_s], row.split(",")
  end

  test "the CSV export honours the filters" do
    get people_retention_report_path(format: :csv, status: Person::RETIRED)

    assert_response :success
    assert_equal 2, response.body.split("\n").size, "header plus the one retired Ranger"
  end

  # A Ranger can be listed on the strength of a shift the Clubhouse does not
  # credit them a year for -- six hours are needed from 2025 on.
  test "a Ranger with no credited year is listed with dashes" do
    short = rangering_person("Shortest", years: [])

    get people_retention_report_path

    assert_includes roster_callsigns, short.callsign
    assert_select "select#last_year option[value=?]", RetentionReport::NO_YEARS

    assert_equal ["—", "—"], year_cells(short), "First Year and Last Year read as a dash"
  end

  # A select navigates with the other filter still applied, so its counts have
  # to promise the roster the choice delivers.
  test "each select counts what its choice will deliver" do
    get people_retention_report_path(last_year: @years.first(2).last.to_s)

    assert_response :success
    assert_select "select#status option[value=?]", Person::ACTIVE, text: "active (1)"
    assert_select "select#status option[value=?]", Person::RETIRED, text: "retired (0)"
  end

  test "the sidebar offers the report to a VC" do
    sign_in_as(@vc)
    get people_retention_report_path

    assert_select "a[href=?]", people_retention_report_path
  end

  private

  def roster_callsigns
    css_select("#retention-report-roster th[scope=row]").map { |cell| cell.text.strip }
  end

  # The First Year and Last Year cells of one person's row.
  def year_cells(person)
    row = css_select("#retention-report-roster tbody tr")
            .find { |tr| tr.css("th").text.strip == person.callsign }
    assert_not_nil row, "#{person.callsign} is not on the page"

    row.css("td").map { |cell| cell.text.strip }[2..3]
  end

  def stats_text
    css_select("div.flex.flex-row.flex-wrap").first&.text.to_s.squish
  end

  def rangering_person(callsign, status: Person::ACTIVE, years: [])
    person = create_person(callsign, status:, years:)
    Timesheet.create!(person:, position: @ood, is_echelon: false,
                      on_duty: Time.local(@years.last, 8, 28, 10, 0, 0),
                      off_duty: Time.local(@years.last, 8, 28, 18, 0, 0),
                      additional_notes: "test shift")
    person
  end
end
