# frozen_string_literal: true

require "test_helper"

class Vc::HandleCheckerControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  SCOPE = Vc::HandleCheckerForm::PARAM_SCOPE

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

    @ranger = person(:active_ranger)
  end

  # The rendered page as plain text. Conflict descriptions wrap the matching
  # callsign in a link, so they are not contiguous in the markup.
  def page_text = Nokogiri::HTML5(response.body).text.squish

  # Only the rules a test cares about, so unrelated rules stay quiet.
  def check_params(handle: nil, names: nil, rule_ids: ["substring"], **overrides)
    {
      SCOPE => {
        "configured" => "1",
        "handle" => handle,
        "names" => names,
        "rule_ids" => rule_ids,
        "entity_types" => ["#{@ranger.status} ranger"],
        "include_vintage" => "0"
      }.compact.merge(overrides.transform_keys(&:to_s))
    }
  end

  test "admin can view the handle checker" do
    sign_in_as(@admin)

    get vc_handle_checker_path

    assert_response :success
    assert_match "Handle Checker", response.body
    assert_match "No handles checked yet", response.body
  end

  test "a non-hash check param is ignored rather than raising" do
    sign_in_as(@admin)

    ["#{SCOPE}=x", "#{SCOPE}[]=a&#{SCOPE}[]=b", SCOPE].each do |query|
      get "#{vc_handle_checker_path}?#{query}"

      assert_response :success
      assert_match "No handles checked yet", response.body
    end
  end

  test "vc can view the handle checker" do
    sign_in_as(@vc)

    get vc_handle_checker_path

    assert_response :success
  end

  test "event management cannot view the handle checker" do
    sign_in_as(@em)

    get vc_handle_checker_path

    assert_redirected_to me_root_path
  end

  test "checking a handle reports a conflict with an existing callsign" do
    sign_in_as(@admin)

    get vc_handle_checker_path, params: check_params(handle: @ranger.callsign)

    assert_response :success
    assert_match "#{@ranger.callsign} is already in use", page_text
    assert_match "high priority", page_text
    assert_match "• Substring", page_text
  end

  test "checking a handle links to the conflicting person" do
    sign_in_as(@admin)

    get vc_handle_checker_path, params: check_params(handle: @ranger.callsign)

    assert_match person_path(@ranger), response.body
  end

  test "a handle with no conflicts reports as clear" do
    sign_in_as(@admin)

    get vc_handle_checker_path, params: check_params(handle: "Zzyzxqqq")

    assert_response :success
    assert_match "No conflicts found", response.body
  end

  test "a reserved handle reports its reason" do
    sign_in_as(@admin)
    reservation = handle_reservation(:slur)

    get vc_handle_checker_path,
        params: check_params(handle: reservation.handle,
                             entity_types: [HandleReservation::TYPE_SLUR])

    assert_match "#{reservation.handle} is a slur", page_text
    assert_match reservation.reason, page_text
  end

  test "the history is re-checked on every request" do
    sign_in_as(@admin)

    get vc_handle_checker_path, params: check_params(handle: "Zzyzxqqq", names: [@ranger.callsign])

    assert_response :success
    assert_match "Zzyzxqqq", response.body
    assert_match "#{@ranger.callsign} is already in use", page_text
  end

  test "turning off a rule hides conflicts already in the history" do
    sign_in_as(@admin)

    get vc_handle_checker_path,
        params: check_params(names: [@ranger.callsign], rule_ids: ["min-length"])

    assert_response :success
    assert_no_match(/is already in use/, page_text)
  end

  test "the history keeps a checked handle only once" do
    sign_in_as(@admin)

    get vc_handle_checker_path, params: check_params(handle: "Repeated", names: ["Repeated"])

    assert_response :success
    assert_equal 1, response.body.scan(/name="check\[names\]\[\]" value="Repeated"/).count
  end

  test "the history is capped" do
    sign_in_as(@admin)
    names = (1..(Vc::HandleCheckerForm::MAX_HISTORY + 5)).map { |index| "Handle#{index}" }

    get vc_handle_checker_path, params: check_params(names: names)

    assert_response :success
    assert_equal Vc::HandleCheckerForm::MAX_HISTORY,
                 response.body.scan(/name="check\[names\]\[\]"/).count
  end

  test "a first visit enables every rule but eye rhymes" do
    sign_in_as(@admin)

    get vc_handle_checker_path

    assert_response :success
    assert_select "input[name='check[rule_ids][]'][value='substring'][checked]"
    assert_select "input[name='check[rule_ids][]'][value='eye-rhyme'][checked]", false
  end

  test "a first visit checks every handle type but past prospective" do
    sign_in_as(@admin)

    get vc_handle_checker_path

    assert_response :success
    assert_select "input[name='check[entity_types][]'][value='active ranger'][checked]"
    assert_select "input[name='check[entity_types][]'][value='past prospective ranger']"
    assert_select "input[name='check[entity_types][]'][value='past prospective ranger'][checked]", false
  end

  test "a submitted form with no rules chosen keeps them all off" do
    sign_in_as(@admin)

    get vc_handle_checker_path,
        params: { SCOPE => { "configured" => "1", "handle" => @ranger.callsign } }

    assert_response :success
    assert_no_match(/is already in use/, page_text)
    assert_select "input[name='check[rule_ids][]'][checked]", false
  end

  test "a vintage callsign is reported even when its status is switched off" do
    sign_in_as(@admin)
    @ranger.update_columns(vintage: true)

    get vc_handle_checker_path,
        params: check_params(handle: @ranger.callsign, entity_types: ["no one ranger"],
                             include_vintage: "1")

    assert_match "#{@ranger.callsign} is already in use", page_text
  end

  test "switching off a status hides its callsigns" do
    sign_in_as(@admin)

    get vc_handle_checker_path,
        params: check_params(handle: @ranger.callsign, entity_types: ["no one ranger"])

    assert_response :success
    assert_no_match(/is already in use/, page_text)
  end

  test "blank entries are dropped from the history" do
    sign_in_as(@admin)

    get vc_handle_checker_path, params: check_params(names: ["Kept", "", "   "])

    assert_response :success
    assert_equal 1, response.body.scan(/name="check\[names\]\[\]"/).count
  end

  test "a hand edited scalar history parameter is tolerated" do
    sign_in_as(@admin)

    get vc_handle_checker_path,
        params: { SCOPE => { "configured" => "1", "names" => @ranger.callsign,
                             "rule_ids" => ["substring"],
                             "entity_types" => ["#{@ranger.status} ranger"] } }

    assert_response :success
    assert_match "#{@ranger.callsign} is already in use", page_text
  end

  test "the reset link appears only while narrowed" do
    sign_in_as(@admin)

    get vc_handle_checker_path, params: check_params(handle: "Anything")

    assert_response :success
    assert_select "a", text: "Reset Rules and Types"
  end

  test "no reset link on a first visit" do
    sign_in_as(@admin)

    get vc_handle_checker_path

    assert_response :success
    assert_select "a", { text: "Reset Rules and Types", count: 0 }
  end

  test "the reset link keeps the checked handles" do
    sign_in_as(@admin)

    get vc_handle_checker_path, params: check_params(handle: "Kept")

    assert_select "a[href*='names%5D%5B%5D=Kept']"
  end

  test "clear history keeps the rule selection" do
    sign_in_as(@admin)

    get vc_handle_checker_path, params: check_params(handle: @ranger.callsign, rule_ids: ["min-length"])

    assert_response :success
    assert_select "a[href*='rule_ids%5D%5B%5D=min-length']"
  end
end
