# frozen_string_literal: true

require "test_helper"

class Vc::ShinyPennyReportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  YEAR = 2012

  setup do
    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    @em = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@em, Role::EVENT_MANAGEMENT)
  end

  def mint_penny(person)
    Position.create!(id: Position::ALPHA, title: "Alpha")
    PersonStatus.create!(person:, old_status: Person::PROSPECTIVE, new_status: Person::ACTIVE,
                         created_at: Time.zone.parse("2012-09-05 12:00"))
    Timesheet.create!(person:, position_id: Position::ALPHA, on_duty: Time.zone.parse("2012-08-28 18:00"),
                      additional_notes: "test shift")
  end

  test "admin can view the report" do
    sign_in_as(@admin)

    get vc_shiny_penny_report_path

    assert_response :success
    assert_match "Shiny Pennies", response.body
  end

  test "vc can view the report" do
    sign_in_as(@vc)

    get vc_shiny_penny_report_path

    assert_response :success
  end

  test "event management cannot view the report" do
    sign_in_as(@em)

    get vc_shiny_penny_report_path

    assert_redirected_to me_root_path
  end

  test "lists each shiny penny with a link to their profile" do
    sign_in_as(@admin)
    penny = person(:prospective_ranger)
    mint_penny(penny)

    get vc_shiny_penny_report_path(year: YEAR)

    assert_response :success
    assert_match "Showing 1 Shiny Penny", response.body
    assert_match person_path(penny), response.body
    assert_match penny.callsign, response.body
  end

  test "csv export returns one row per shiny penny" do
    sign_in_as(@admin)
    penny = person(:prospective_ranger)
    mint_penny(penny)

    get vc_shiny_penny_report_path(year: YEAR, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match 'filename="2012-shiny-pennies.csv"', response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Email,First Name,Last Name", lines.first
    assert_match(/\A#{penny.callsign},/, lines.second)
  end
end
