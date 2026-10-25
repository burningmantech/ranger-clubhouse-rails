# frozen_string_literal: true

require "test_helper"

class RegisterControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear
    Current.reset
    Setting.find_or_initialize_by(name: Setting::ACCOUNT_CREATION_EMAIL)
           .update!(value: "vc@example.com")
    close_registration(false)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def close_registration(closed)
    Setting.find_or_initialize_by(name: Setting::AUDITOR_REGISTRATION_DISABLED)
           .update!(value: closed.to_s)
  end

  # The training server is told apart by an environment variable, and a request
  # resets Current before the page runs, so the variable is what a test sets.
  def on_training_server
    previous = ENV.fetch("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME", nil)
    ENV["RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"] = "the middle of the burn"
    yield
  ensure
    ENV["RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"] = previous
  end

  def account_params(**overrides)
    {
      register_form: {
        email: "sparkplug@example.com",
        first_name: "Spark", mi: "", last_name: "Plug",
        country: "US", street1: "1 Example St", apt: "", street2: "",
        city: "Example City", state: "NV", zip: "99999",
        home_phone: "775 555 0199", alt_phone: "",
        password: "a-good-password", password_confirmation: "a-good-password",
        intent: "Sitin", human_answer: RegisterForm::HUMAN_ANSWER.to_s
      }.merge(overrides)
    }
  end

  # ------------------------------------------------------------------ steps

  test "the page opens by asking why the reader is here" do
    get register_path

    assert_response :success
    assert_select "h1", text: /Auditor Registration/
    assert_match "Why You're Here", response.body
  end

  test "someone here to volunteer is sent to the Volunteer Form" do
    get register_path(step: "volunteer")

    assert_response :success
    assert_match "Wrong Place to Become a Ranger", response.body
    assert_select "a[href=?]", "https://profiles.burningman.org"
  end

  test "the step before the form says auditing is not a path to becoming a Ranger" do
    get register_path(step: "acknowledge")

    assert_response :success
    assert_match "not a path to becoming a Black Rock Ranger", response.body
  end

  test "the form asks the sum and the reason" do
    get register_path(step: "form")

    assert_response :success
    assert_match RegisterForm::HUMAN_QUESTION, response.body
    assert_select "form[action=?]", register_path(step: "form")
  end

  test "a step no one recognises starts over rather than failing" do
    get register_path(step: "wander-off")

    assert_response :success
    assert_match "Why You're Here", response.body
  end

  test "somebody already signed in has nothing to register for" do
    sign_in_as(person(:active_ranger))

    get register_path

    assert_redirected_to me_root_path
  end

  # --------------------------------------------------------------- creation

  test "a filled-in form opens the account and says so" do
    assert_difference "Person.count", 1 do
      post register_path, params: account_params
    end

    # Sent on to a page of its own, so reloading the congratulations cannot
    # offer to open a second account.
    assert_response :see_other
    assert_redirected_to register_path(step: "success")
    person = Person.find_by(email: "sparkplug@example.com")
    assert_equal Person::AUDITOR, person.status

    follow_redirect!
    assert_response :success
    assert_match person.callsign, response.body
    assert_select "a[href=?]", root_path
    # The callsign travels in the flash to get here, and everything left in the
    # flash is shown as a message in the corner of the page.
    assert_select "[data-controller=toast]", false,
                  "the callsign is not also announced as a message"
  end

  test "the finished page starts the reader over once its account is forgotten" do
    get register_path(step: "success")

    assert_redirected_to register_path
  end

  test "someone who wants to become a Ranger is turned around, not signed up" do
    assert_no_difference "Person.count" do
      post register_path, params: account_params(intent: "Ranger")
    end

    assert_response :see_other
    assert_redirected_to register_path(step: "volunteer")
    follow_redirect!
    assert_match "Wrong Place to Become a Ranger", response.body
  end

  test "a wrong answer to the sum comes back to the form" do
    assert_no_difference "Person.count" do
      post register_path, params: account_params(human_answer: "3")
    end

    assert_response :unprocessable_entity
    assert_match RegisterForm::HUMAN_QUESTION, response.body
  end

  test "what was already typed comes back with the errors" do
    post register_path, params: account_params(human_answer: "3")

    assert_response :unprocessable_entity
    assert_select "input[name=?][value=?]", "register_form[first_name]", "Spark"
  end


  test "a request whose answers are not a form is a bad request, not a crash" do
    assert_no_difference "Person.count" do
      post register_path, params: { register_form: "not-a-form" }
    end

    assert_response :bad_request
  end

  test "the finished page survives the season closing under it" do
    post register_path, params: account_params
    assert_response :see_other

    close_registration(true)
    follow_redirect!

    assert_response :success
    assert_match Person.find_by(email: "sparkplug@example.com").callsign, response.body
    assert_select "[data-controller=toast]", false,
                  "the callsign is not announced as a message"
  end

  test "opening the page elsewhere does not spend the callsign" do
    post register_path, params: account_params
    success_url = response.location

    # Something else asks for the page before the reader's browser follows on.
    get register_path

    get success_url
    assert_response :success
    assert_match Person.find_by(email: "sparkplug@example.com").callsign, response.body
  end

  test "the answers a rejected form sends back are not kept in the request log" do
    Setting.find_or_initialize_by(name: Setting::REQUEST_LOG_ENABLED).update!(value: "true")

    post register_path, params: account_params(human_answer: "3")
    assert_response :unprocessable_entity

    entry = RequestLog.order(:id).last
    assert_nil entry&.response_payload,
               "a rejected registration does not store the page carrying the reader's address"
  end

  # ----------------------------------------------------------- closed doors

  test "a closed season says so instead of showing the form" do
    close_registration(true)

    get register_path

    assert_response :service_unavailable
    assert_match "Registration Is Closed", response.body
  end

  test "a closed season refuses to open an account" do
    close_registration(true)

    assert_no_difference "Person.count" do
      post register_path, params: account_params
    end

    assert_response :service_unavailable
  end

  test "the training server never opens accounts" do
    on_training_server do
      get register_path

      assert_response :service_unavailable
      assert_match "Registration Is Closed", response.body

      assert_no_difference "Person.count" do
        post register_path, params: account_params
      end
      assert_response :service_unavailable
    end
  end
end
