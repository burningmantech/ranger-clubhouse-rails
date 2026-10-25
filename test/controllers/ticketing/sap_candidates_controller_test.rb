# frozen_string_literal: true

require "test_helper"

# Ticketing > SAP Candidates: who the three-year look-back and this year's
# sign-ups turn up, which documents rule a person out, and the CSV export.
#
# The action reads the whole access_document, timesheet, and person_slot tables
# and the shared fixtures belong to other suites, so every test starts from
# empty tables and builds exactly the rows it needs.
class Ticketing::SapCandidatesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  START_YEAR = 2023 # the third event before YEAR

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @ticketing = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @retired = person(:retired_ranger)
    @other = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Documents")
    grant_role(@admin, Role::ADMIN)
    grant_role(@ticketing, Role::EDIT_ACCESS_DOCS)

    AccessDocument.delete_all
    # The timesheet fixtures put 2023 and 2024 shifts on people this report
    # looks at, which would seed the pool before a test says anything.
    Timesheet.delete_all
    PersonSlot.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look --------------------------------------------------------

  test "the report renders for an admin" do
    sign_up(@admin)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_select "a[href=?]", person_path(@admin), text: @admin.callsign
  end

  test "the report renders with only the edit access documents role" do
    sign_in_as(@ticketing)
    sign_up(@other)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_equal [@other.callsign], rendered_callsigns
  end

  test "the report is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_sap_candidates_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to view ticketing reports.", flash[:error]
  end

  # --- who lands on the list ------------------------------------------------

  test "a sign-up with nothing on file is a candidate" do
    sign_up(@admin)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_equal ["No"], rendered_ticket_flags
    assert_equal({ "SAP Candidates" => "1", "Holds a Ticket" => "0", "Signed Up, No Ticket" => "1" },
                 rendered_stats)
  end

  test "a recent volunteer holding a ticket is a candidate" do
    ticket = ticket_for(@admin)
    worked(@admin, YEAR - 2)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_equal ["Yes"], rendered_ticket_flags
    assert_match "RAD-#{ticket.id} SPT qualified", response.body
    assert_equal({ "SAP Candidates" => "1", "Holds a Ticket" => "1", "Signed Up, No Ticket" => "0" },
                 rendered_stats)
  end

  # Shifts alone say nothing about this year's plans.
  test "a recent volunteer with no ticket and no sign-up is not a candidate" do
    worked(@admin, YEAR - 1)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_empty rendered_callsigns
  end

  test "shifts before the look-back do not put anyone in the pool" do
    worked(@admin, START_YEAR - 1)
    ticket_for(@admin)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_empty rendered_callsigns
  end

  # --- what rules a person out ---------------------------------------------

  test "a sap in any current status rules the person out" do
    AccessDocument::CURRENT_STATUSES.each do |status|
      AccessDocument.delete_all
      PersonSlot.delete_all
      sign_up(@admin)
      ticket_for(@admin, type: AccessDocument::SAP, status:)

      get ticketing_sap_candidates_path

      assert_response :success
      assert_empty rendered_callsigns, "a #{status} SAP should rule the person out"
    end
  end

  # A staff credential is an event ticket and a SAP in one, in every current
  # status, so it settles the question on its own.
  test "a staff credential rules the person out even when banked" do
    sign_up(@admin)
    ticket_for(@admin, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::BANKED)
    worked(@other, YEAR - 1)
    ticket_for(@other)
    ticket_for(@other, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::BANKED)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_empty rendered_callsigns
  end

  # --- which statuses count -------------------------------------------------

  test "a retired ranger signed up this year is a candidate" do
    sign_up(@retired)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_equal [@retired.callsign], rendered_callsigns
  end

  # The look-back is narrower than the sign-up list on purpose.
  test "a retired ranger with only past shifts and a ticket is not a candidate" do
    worked(@retired, YEAR - 1)
    ticket_for(@retired)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_empty rendered_callsigns
  end

  test "an inactive ranger with past shifts and a ticket is a candidate" do
    worked(@outsider, YEAR - 1)
    ticket_for(@outsider)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_equal [@outsider.callsign], rendered_callsigns
  end

  test "an echelon ranger never appears" do
    worked(@ticketing, YEAR - 1)
    sign_up(@ticketing)
    ticket_for(@ticketing)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_empty rendered_callsigns
  end

  # --- the columns ----------------------------------------------------------

  test "the years column lists distinct event years inside the look-back" do
    sign_up(@admin)
    worked(@admin, START_YEAR - 1)
    worked(@admin, START_YEAR)
    worked(@admin, START_YEAR)
    worked(@admin, YEAR - 1)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_match "Years with Shifts Since #{START_YEAR}", response.body
    assert_equal ["#{START_YEAR}, #{YEAR - 1}"], rendered_years
  end

  test "the schedule lists this year's sign-ups in start order" do
    sign_up(@admin, begins: Time.local(YEAR, 8, 30, 9, 0, 0), description: "Later shift")
    sign_up(@admin, begins: Time.local(YEAR, 8, 25, 9, 0, 0), description: "Earlier shift")
    sign_up(@admin, begins: Time.local(YEAR - 1, 8, 25, 9, 0, 0), description: "Last year")

    get ticketing_sap_candidates_path

    assert_response :success
    assert_equal ["2 sign-ups"], rendered_signup_summaries
    assert_not_includes response.body, "Last year"
    assert_operator response.body.index("Earlier shift"), :<, response.body.index("Later shift")
    assert_match "Tue Aug 25 @ 09:00", response.body
  end

  test "rows are sorted by callsign regardless of case" do
    sign_up(@admin)
    sign_up(@other)

    get ticketing_sap_candidates_path

    assert_response :success
    assert_equal [@admin, @other].map(&:callsign).sort_by(&:downcase), rendered_callsigns
  end

  test "the empty report says so" do
    get ticketing_sap_candidates_path

    assert_response :success
    assert_match "No Ranger appears to need a SAP right now", response.body
  end

  # --- CSV export -----------------------------------------------------------

  test "the csv export returns the rows under the expected filename" do
    ticket = ticket_for(@admin)
    worked(@admin, YEAR - 1)
    sign_up(@admin, begins: Time.local(YEAR, 8, 25, 9, 0, 0), description: "Dirt shift")

    get ticketing_sap_candidates_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match %(filename="#{YEAR}-sap-candidates.csv"), response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Email,Has SPT?,Years With Shifts,Sign Ups", lines.first
    assert_equal 2, lines.size
    assert_equal [@admin.callsign, @admin.status, @admin.email, "RAD-#{ticket.id} SPT qualified",
                  (YEAR - 1).to_s, "Tue Aug 25 @ 09:00 Training Lead Dirt shift"].join(","),
                 lines.second
  end

  test "the csv export spells out a missing ticket" do
    sign_up(@admin)

    get ticketing_sap_candidates_path(format: :csv)

    assert_response :success
    assert_equal "NO SPT", response.body.split("\n").second.split(",")[3]
  end

  private

  # A qualified special price ticket by default: the plainest reason to appear.
  # delivery_method is spelled out because the column is NOT NULL and the model
  # only fills it in on a status change, as the fixtures do.
  def ticket_for(holder, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED)
    AccessDocument.create!(person: holder, type:, status:, source_year: YEAR,
                           delivery_method: AccessDocument::DELIVERY_NONE,
                           expiry_date: "#{YEAR + 3}-09-15")
  end

  # Timesheets are stored as machine-local wall clock, so shifts are built the
  # same way the report builds its look-back boundary. additional_notes is
  # required by the model's audit trail on every create.
  def worked(person, year)
    on_duty = Time.local(year, 8, 28, 10, 0, 0)
    Timesheet.create!(person:, position: positions(:ood_position), on_duty:, off_duty: on_duty + 6.hours,
                      additional_notes: "test shift")
  end

  def sign_up(person, begins: Time.local(YEAR, 8, 28, 9, 0, 0), description: nil)
    slot = Slot.create!(position: positions(:training_lead), begins:, ends: begins + 4.hours,
                        max: 10, active: true, description:)
    PersonSlot.create!(person:, slot:)
  end

  # The stat row above the table, as { label => value }.
  def rendered_stats
    css_select("div.rounded-lg.p-3.text-center").to_h do |box|
      parts = box.css("div")
      [parts.last.text.strip, parts.first.text.strip]
    end
  end

  # The callsign heading each rendered row of the table.
  def rendered_callsigns
    css_select("tbody th").map { |cell| cell.text.strip }
  end

  def rendered_ticket_flags
    rendered_column(1).map { |cell| cell.css(".badge").text.strip }
  end

  def rendered_years
    rendered_column(2).map { |cell| cell.text.strip }
  end

  def rendered_signup_summaries
    rendered_column(3).map { |cell| cell.css("summary").text.strip }
  end

  def rendered_column(index)
    css_select("tbody tr").map { |row| row.css("td")[index] }
  end
end
