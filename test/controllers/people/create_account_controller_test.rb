# frozen_string_literal: true

require "test_helper"

class People::CreateAccountControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # Fixture people carry a country label rather than a code, so a test that
  # saves an address picks a country and a state of its own.
  def account_params(**overrides)
    {
      create_account_form: {
        callsign: "Sparkplug", email: "sparkplug@example.com", status: Person::ECHELON,
        first_name: "Spark", mi: "", last_name: "Plug",
        country: "US", street1: "1 Example St", apt: "", street2: "",
        city: "Example City", state: "NV", zip: "99999",
        home_phone: "775 555 0199",
        password: "a-good-password", password_confirmation: "a-good-password"
      }.merge(overrides)
    }
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get people_create_account_path

    assert_response :success
    assert_select "h1", /Create Account/
    assert_select "select[name=?] option[selected][value=?]", "create_account_form[status]", Person::ECHELON
    assert_select "select[name=?] option[selected][value=?]", "create_account_form[country]", "US"
    # Two ways off the page without creating anything.
    assert_select "a[aria-label=?][href=?]", "Back to Clubhouse Dashboard", me_root_path
    assert_select "main a[href=?]", me_root_path, text: "Cancel"
    assert_unique_dom_ids
  end

  test "someone without the admin role is turned away" do
    sign_in_as(@outsider)

    get people_create_account_path

    assert_redirected_to me_root_path
  end

  test "a signed out visitor is sent to login" do
    sign_out

    get people_create_account_path

    assert_redirected_to root_path
  end

  test "someone without the admin role cannot post an account" do
    sign_in_as(@outsider)

    assert_no_difference "Person.count" do
      post people_create_account_path, params: account_params
    end

    # Asserted as well as the count, so a refusal cannot be confused with a
    # request that simply fell over.
    assert_redirected_to me_root_path
  end

  # ---------------------------------------------------------------- create

  test "a filled in form opens the account" do
    assert_difference "Person.count", 1 do
      post people_create_account_path, params: account_params
    end

    created = Person.find_by(callsign: "Sparkplug")
    assert_redirected_to person_path(created)
    assert_equal "sparkplug@example.com", created.email
    assert_equal Person::ECHELON, created.status
    assert_equal "Spark", created.first_name
    assert_equal "Plug", created.last_name
    assert_equal "1 Example St", created.street1
    assert_equal "Example City", created.city
    assert_equal "NV", created.state
    assert_equal "99999", created.zip
    assert_equal "US", created.country
    assert_equal "+17755550199", created.home_phone
    assert_equal Current.today, created.status_date
    assert created.authenticate("a-good-password"), "the typed password signs the person in"

    # The page the admin lands on has to open, not just be pointed at.
    follow_redirect!
    assert_response :success
  end

  test "opening an account starts its status history" do
    assert_difference "PersonStatus.count", 1 do
      post people_create_account_path, params: account_params
    end

    created = Person.find_by(callsign: "Sparkplug")
    row = PersonStatus.where(person_id: created.id).last
    assert_equal "", row.old_status
    assert_equal Person::ECHELON, row.new_status
    assert_equal CreateAccountForm::STATUS_REASON, row.reason
    assert_equal @admin.id, row.person_source_id
  end

  # An account opened straight at Active has to arrive with the positions every
  # Ranger gets, the same as one moved to Active later. Without them the person
  # cannot be put on a shift, and setting the status again would change nothing.
  test "an account opened as active arrives with the positions that go with it" do
    everyones = Position.create!(title: "Everyone Position", active: true,
                                 all_rangers: true, no_training_required: true)

    post people_create_account_path, params: account_params(status: Person::ACTIVE)

    created = Person.find_by(callsign: "Sparkplug")
    granted = PersonPosition.where(person_id: created.id).pluck(:position_id)
    assert_includes granted, everyones.id, "the position every Ranger holds is granted"
  end

  test "the action log entry keeps no secrets" do
    post people_create_account_path, params: account_params

    created = Person.find_by(callsign: "Sparkplug")
    entry = ActionLog.where(event: "person-create", target_person_id: created.id).last
    assert_not_nil entry, "opening an account is recorded"

    assert_equal "Sparkplug", entry.data["callsign"]
    Person.audit_exclude.each do |column|
      assert_not entry.data.key?(column), "#{column} must stay out of the action log"
    end
  end

  # ------------------------------------------------------------- refusals

  # Each of these must leave nothing behind and show the form again with the
  # values still filled in.
  {
    "a missing callsign" => { callsign: "" },
    "a callsign somebody already has" => { callsign: "testranger" },
    "an email address somebody already has" => { callsign: "Newname", email: "testranger@example.com" },
    "a missing state where the country has them" => { state: "" },
    "two different passwords" => { password_confirmation: "a-different-password" },
    "a password that is too short" => { password: "short12", password_confirmation: "short12" },
    "a missing phone number" => { home_phone: "" }
  }.each do |description, overrides|
    test "#{description} is refused" do
      assert_no_difference ["Person.count", "PersonStatus.count"] do
        post people_create_account_path, params: account_params(**overrides)
      end

      assert_response :unprocessable_entity
      assert_select "#form-error-summary"
      # Every field comes back filled in except the two passwords, which are
      # never sent back to the browser.
      assert_select "input[name=?][value=?]", "create_account_form[first_name]", "Spark"
      assert_select "input[name=?]:not([value])", "create_account_form[password]"
    end
  end

  # Someone who has already left the department may be on file with no address
  # at all, and an account opened for the record should not have to invent one.
  test "a status that has left the department is accepted with no address" do
    assert_difference "Person.count", 1 do
      post people_create_account_path,
           params: account_params(status: Person::RETIRED, country: "", street1: "",
                                  city: "", state: "", zip: "")
    end

    created = Person.find_by(callsign: "Sparkplug")
    assert_equal Person::RETIRED, created.status
    assert_equal "", created.street1
  end

  # A British address with a British number written the British way: the
  # number is read against the address, and stored with its country code.
  test "a country without states is accepted with no state" do
    assert_difference "Person.count", 1 do
      post people_create_account_path, params: account_params(country: "GB", state: "", home_phone: "0121 496 0497")
    end

    created = Person.find_by(callsign: "Sparkplug")
    assert_equal "GB", created.country
    assert_equal "", created.state
    assert_equal "+441214960497", created.home_phone
  end

  # "775 555 0199" is a Nevada number and a valid UK mobile. From a British
  # address it could be either, so it is turned back rather than guessed.
  test "a number that reads two ways from the address is turned back" do
    assert_no_difference "Person.count" do
      post people_create_account_path, params: account_params(country: "GB", state: "")
    end

    assert_response :unprocessable_entity
    assert_match I18n.t("errors.messages.phone_invalid", attribute: "Primary phone"), response.body
    assert_select "input[name=?][value=?]", "create_account_form[home_phone]", "775 555 0199"
  end
end
