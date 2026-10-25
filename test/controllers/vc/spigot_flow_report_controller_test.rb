# frozen_string_literal: true

require "test_helper"

class Vc::SpigotFlowReportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include PersonPhotoTestHelper # create_photo
  include ReportCardTestHelper  # assert_report_card / card_answer / assert_no_card_question

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

  # The year must sit between SpigotFlowReport::SALESFORCE_CUTOVER_YEAR (below
  # it the report reads person_status, not applications) and the current year
  # (setup_year rejects future years).
  def create_application(person:)
    ProspectiveApplication.create!(
      bpguid: "SPIGOT-CTRL", email: "spigot-ctrl@example.com", year: 2025,
      status: ProspectiveApplication::STATUS_CREATED, person:,
      created_at: Time.zone.parse("2025-03-01 10:00")
    )
  end

  test "admin can view the report" do
    sign_in_as(@admin)

    get vc_spigot_flow_report_path

    assert_response :success
    assert_match "Spigot Flow", response.body
  end

  test "vc can view the report" do
    sign_in_as(@vc)

    get vc_spigot_flow_report_path

    assert_response :success
  end

  test "event management cannot view the report" do
    sign_in_as(@em)

    get vc_spigot_flow_report_path

    assert_redirected_to me_root_path
  end

  test "milestone counts link to the people who reached them" do
    sign_in_as(@admin)
    applicant = person(:prospective_ranger)
    create_application(person: applicant)

    get vc_spigot_flow_report_path(year: 2025)

    assert_response :success
    assert_match "2025-03-01", response.body
    assert_match "Totals", response.body
    assert_match person_path(applicant), response.body
    assert_match applicant.callsign, response.body
  end

  # Every pair in the card explains a row or a column of the table, so a year
  # with no applicant activity has neither. No fixture records any for 2024.
  test "the card explains the table where there is one" do
    sign_in_as(@admin)
    create_application(person: person(:prospective_ranger))

    get vc_spigot_flow_report_path(year: 2025)

    assert_report_card

    get vc_spigot_flow_report_path(year: 2024)

    assert_match(/No applicant activity was found/, response.body)
    assert_report_card count: 0
  end

  # The row for milestones carried over from an earlier intake is drawn only
  # when there is one, so the pair about it comes and goes with the row.
  test "the card explains the previous-years row only when the table has one" do
    question = "What is the “Previous year(s)” row?"
    sign_in_as(@admin)
    applicant = person(:prospective_ranger)
    create_application(person: applicant)
    photo = create_photo(person: applicant, status: PersonPhoto::APPROVED,
                         reviewed_at: Time.zone.parse("2024-12-01 10:00"))

    get vc_spigot_flow_report_path(year: 2025)

    assert_match(/prior intake cycle/, card_answer(question))

    PersonPhoto.where(id: photo.id).delete_all
    get vc_spigot_flow_report_path(year: 2025)

    assert_report_card
    assert_no_card_question question
  end

  test "csv export returns counts per day" do
    sign_in_as(@admin)
    create_application(person: person(:prospective_ranger))

    get vc_spigot_flow_report_path(year: 2025, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match 'filename="2025-spigot-flow.csv"', response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Date,Imported,Created,First Login,BMID Photo Approved,Online Trained," \
                 "Sign Up For Training,Trained,Dropped,Alpha Sign Up", lines.first
    assert_includes lines, "2025-03-01,1,1,,,,,,,"
  end
end
