# frozen_string_literal: true

require "test_helper"

class Vc::ThankYouCardsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    # None of these three rangered a shift, so signing in never changes the list.
    @admin = person(:retired_ranger)
    @vc = person(:inactive_ranger)
    @em = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@em, Role::EVENT_MANAGEMENT)
  end

  test "admin can view the list" do
    sign_in_as(@admin)

    get vc_thank_you_cards_path

    assert_response :success
    # The sidebar names this page on every VC page, so assert on the heading.
    assert_select "h1", text: /#{Current.year} Thank You Cards/
  end

  test "vc can view the list" do
    sign_in_as(@vc)

    get vc_thank_you_cards_path

    assert_response :success
  end

  test "event management cannot view the list" do
    sign_in_as(@em)

    get vc_thank_you_cards_path

    assert_redirected_to me_root_path
  end

  test "lists everyone who rangered that year and skips the statuses we do not mail" do
    sign_in_as(@admin)

    get vc_thank_you_cards_path(year: 2024)

    assert_response :success
    assert_match person(:active_ranger).callsign, response.body
    assert_match person(:echelon_ranger).callsign, response.body
    assert_no_match(/#{Regexp.escape(person(:auditor_ranger).callsign)}/, response.body)
  end

  # Gives a deceased person a 2023 shift so the optional statuses have
  # something to hide and show.
  def deceased_with_a_shift
    shift_in_2023(person(:deceased_ranger))
  end

  # No fixture carries the resigned status, so one is borrowed. Without this
  # the filter could ignore the status entirely and the tests would not notice.
  def resigned_with_a_shift
    person(:plate_collision_ranger).tap do |quit|
      quit.update_columns(status: Person::RESIGNED)
      shift_in_2023(quit)
    end
  end

  def shift_in_2023(person)
    person.tap do
      Timesheet.create!(person:, position: positions(:ood_position),
                        on_duty: DateTime.new(2023, 8, 28, 10, 0, 0), additional_notes: "test shift")
    end
  end

  test "leaves out someone we should not be mailing" do
    sign_in_as(@admin)
    gone = deceased_with_a_shift

    get vc_thank_you_cards_path(year: 2023)

    assert_response :success
    assert_no_match(/#{Regexp.escape(gone.callsign)}/, response.body)
  end

  test "puts a skipped status back when the filter asks for it" do
    sign_in_as(@admin)
    gone = deceased_with_a_shift

    get vc_thank_you_cards_path(year: 2023, include_statuses: [Person::DECEASED])

    assert_response :success
    assert_match gone.callsign, response.body
    assert_match "Including: deceased", response.body
  end

  test "asking for one status does not let the others in" do
    sign_in_as(@admin)
    gone = deceased_with_a_shift
    quit = resigned_with_a_shift

    get vc_thank_you_cards_path(year: 2023, include_statuses: [Person::RESIGNED])

    assert_response :success
    assert_match quit.callsign, response.body
    assert_no_match(/#{Regexp.escape(gone.callsign)}/, response.body)
  end

  test "ignores a status the filter does not offer" do
    sign_in_as(@admin)

    get vc_thank_you_cards_path(year: 2023, include_statuses: [Person::BONKED, "nonsense"])

    assert_response :success
    assert_no_match(/Including:/, response.body)
  end

  # A crafted URL sends a hash rather than a list. It must narrow to nothing
  # instead of raising.
  test "ignores a filter that is not a list of statuses" do
    sign_in_as(@admin)

    get vc_thank_you_cards_path(year: 2023, include_statuses: { evil: Person::DECEASED })

    assert_response :success
    assert_no_match(/Including:/, response.body)
  end

  test "counts each status on show" do
    sign_in_as(@admin)

    get vc_thank_you_cards_path(year: 2024)

    assert_response :success
    assert_select "#thank-you-cards-status-counts" do |counts|
      # active_ranger has two 2024 shifts and must still be counted once.
      assert_match(/1\s*active/, counts.text)
      assert_match(/1\s*echelon/, counts.text)
    end
  end

  test "counts a status the filter put back" do
    sign_in_as(@admin)
    deceased_with_a_shift

    get vc_thank_you_cards_path(year: 2023, include_statuses: [Person::DECEASED])

    assert_response :success
    assert_select "#thank-you-cards-status-counts" do |counts|
      assert_match "deceased", counts.text
    end
  end

  test "leaves out someone whose only shift was another year" do
    sign_in_as(@admin)

    get vc_thank_you_cards_path(year: 2023)

    assert_response :success
    assert_match person(:active_ranger).callsign, response.body
    assert_no_match(/#{Regexp.escape(person(:echelon_ranger).callsign)}/, response.body)
  end

  test "says the list is empty without claiming why" do
    sign_in_as(@admin)

    get vc_thank_you_cards_path(year: 2022)

    assert_response :success
    assert_match "No one on the 2022 mailing list", response.body
  end

  # 2025 has one shift, walked by a prospective. The page must not claim
  # no one rangered when somebody did and was filtered out.
  test "does not claim no one rangered when everyone was filtered out" do
    sign_in_as(@admin)

    get vc_thank_you_cards_path(year: 2025)

    assert_response :success
    assert_no_match(/[Nn]obody rangered/, response.body)
  end

  test "flags and counts people with no address on file" do
    sign_in_as(@admin)
    person(:active_ranger).update_columns(street1: "", city: "", state: "", zip: "", apt: "")

    get vc_thank_you_cards_path(year: 2023)

    assert_response :success
    assert_match "No address on file", response.body
    assert_match "1 with no address on file", response.body
  end

  # The column is nullable and shared with another application, so a row can
  # arrive with no email at all.
  test "does not draw an empty link when there is no email" do
    sign_in_as(@admin)
    person(:active_ranger).update_columns(email: nil)

    get vc_thank_you_cards_path(year: 2023)

    assert_response :success
    assert_select "a[href='mailto:']", false
  end

  test "shows the mailing address" do
    sign_in_as(@admin)

    get vc_thank_you_cards_path(year: 2023)

    assert_response :success
    assert_match "123 Main St", response.body
    assert_match "San Francisco, California 94102", response.body
  end

  test "csv export carries the printer columns" do
    sign_in_as(@admin)

    get vc_thank_you_cards_path(year: 2023, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match 'filename="2023-thank-you-cards.csv"', response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Team,First,Last,AKA/ Playa Name,Email Address,Address,Apt,Address 2,City,State,Country,Zip,BPGUID",
                 lines.first

    ranger = person(:active_ranger)
    assert_match(/\ARangers,Test,Ranger,Ranger #{Regexp.escape(ranger.callsign)},/, lines.second)
    assert_match "UNITED STATES", lines.second
    assert_match ranger.bpguid, lines.second
  end

  test "csv export spells out a country code" do
    sign_in_as(@admin)
    person(:active_ranger).update_columns(country: "GB")

    get vc_thank_you_cards_path(year: 2023, format: :csv)

    assert_response :success
    assert_match "UNITED KINGDOM", response.body
  end

  test "csv export follows the same filter as the page" do
    sign_in_as(@admin)
    gone = deceased_with_a_shift

    get vc_thank_you_cards_path(year: 2023, format: :csv)
    assert_no_match(/#{Regexp.escape(gone.callsign)}/, response.body)

    get vc_thank_you_cards_path(year: 2023, include_statuses: [Person::DECEASED], format: :csv)
    assert_match gone.callsign, response.body
  end

  # A name a spreadsheet would run as a formula has to arrive as text.
  test "csv export disarms a formula in a name" do
    sign_in_as(@admin)
    person(:active_ranger).update_columns(first_name: "=cmd|calc")

    get vc_thank_you_cards_path(year: 2023, format: :csv)

    assert_response :success
    assert_match "'=cmd|calc", response.body
  end
end
