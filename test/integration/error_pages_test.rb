# frozen_string_literal: true

require "test_helper"

# The pages a failed request ends on: Page Not Found (the NotFoundPage
# middleware) and the crash page (ErrorPages, config.exceptions_app). The test
# environment shows Rails' debug page instead, so these requests turn the real
# ones on for themselves.
class ErrorPagesTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  SWITCHES = { "action_dispatch.show_exceptions" => :all, "action_dispatch.show_detailed_exceptions" => false }.freeze
  BROWSER_IMAGE = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"

  setup do
    @env_config = Rails.application.env_config
    @saved = @env_config.slice(*SWITCHES.keys)
    @env_config.merge!(SWITCHES)
  end

  teardown { @env_config.merge!(@saved) }

  # ---- Page Not Found ----

  test "signed out, an unknown address is Page Not Found on the door with a way to sign in" do
    get "/no-such-page"

    assert_response :not_found
    assert_select "h1", "Page Not Found"
    assert_select "a[href=?]", root_path, text: "Sign In"
    assert_select "code", "/no-such-page"
    assert_select "#sidebar-drawer", count: 0
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "signed in, an unknown address is Page Not Found inside the shell with a way to the dashboard" do
    sign_in_as person(:active_ranger)
    get "/no-such-page?secret=1"

    assert_response :not_found
    assert_select "h1", "Page Not Found"
    assert_select "#sidebar-drawer"
    assert_select "main a[href=?]", me_root_path, text: "Go to Your Dashboard"
    assert_select "code", "/no-such-page"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "a record that does not exist ends on the same page" do
    sign_in_as person(:active_ranger)
    with_raising(Me::DashboardController, :index, ActiveRecord::RecordNotFound.new("gone")) { get me_root_path }

    assert_response :not_found
    assert_select "h1", "Page Not Found"
    assert_select "code", me_root_path
  end

  test "a form sent to an unknown address ends on the same page" do
    sign_in_as person(:active_ranger)
    post "/no-such-page", headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_response :not_found
    assert_equal "text/html", response.media_type
    assert_select "h1", "Page Not Found"
  end

  test "a past prospective gets the page, not a redirect" do
    sign_in_as person(:past_prospective_ranger)
    get "/no-such-page"

    assert_response :not_found
    assert_select "h1", "Page Not Found"
  end

  # The page is drawn inside the middleware stack, so the session is saved: a
  # message it shows is not shown a second time by the page after it.
  test "a message shown on Page Not Found is not shown again" do
    sign_in_as person(:active_ranger)
    with_action(Me::DashboardController, :index, -> { redirect_to "/no-such-page", error: "Shown once." }) do
      get me_root_path
      follow_redirect!
    end

    assert_response :not_found
    assert_includes response.body, "Shown once."

    get me_root_path

    assert_response :success
    assert_not_includes response.body, "Shown once."
  end

  test "a missing file gets the static page, not the shell" do
    sign_in_as person(:active_ranger)
    get "/favicon.ico", headers: { "Accept" => BROWSER_IMAGE }

    assert_response :not_found
    assert_includes response.body, "This file lives in public/404.html"
  end

  test "a HEAD request for an unknown address gets no body" do
    head "/no-such-page", headers: { "Accept" => "text/html" }

    assert_response :not_found
    assert_empty response.body
  end

  test "a request for JSON still gets the JSON answer" do
    get "/no-such-page", headers: { "Accept" => "application/json" }

    assert_response :not_found
    assert_equal({ "status" => 404, "error" => "Not Found" }, response.parsed_body)
  end

  test "Page Not Found that cannot be drawn is a crash" do
    with_raising(ErrorsController, :not_found) { get "/no-such-page" }

    assert_response :internal_server_error
    assert_select "h1", "The Clubhouse Crashed"
  end

  # ---- The crash page ----

  test "signed in, a crash says so, names the Tech Cadre and leads to the dashboard" do
    sign_in_as person(:active_ranger)
    cookies[:session_id] = Rails.application.message_verifier("signed cookie").generate("any")
    with_raising(Me::DashboardController, :index) { get me_root_path }

    assert_response :internal_server_error
    assert_select "h1", "The Clubhouse Crashed"
    assert_select "a[href^=?]", "mailto:#{EmailAddresses::TECH_CADRE}", minimum: 1
    assert_select "a[href=?]", me_root_path, text: "Go to Your Dashboard"
    assert_select "code", me_root_path
    assert_select "dd", /\A\d{4}-\d\d-\d\d \d\d:\d\d:\d\d [A-Z]+\z/
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "max-age=0, no-store", response.headers["CDN-Cache-Control"]
  end

  test "signed out, a crash leads to the sign-in page" do
    with_raising(SessionsController, :new) { get root_path }

    assert_response :internal_server_error
    assert_select "h1", "The Clubhouse Crashed"
    assert_select "a[href=?]", root_path, text: "Go to the Sign-In Page"
    assert_select "a[href=?]", me_root_path, count: 0
  end

  # The promise the page is built on: whatever broke, it cannot break this too.
  test "the crash page asks the database nothing" do
    env = Rack::MockRequest.env_for("/500", "HTTP_ACCEPT" => "text/html", "action_dispatch.original_path" => "/me/timesheet")
    status = body = nil

    assert_no_queries { status, _headers, body = ErrorPages.call(env.merge(@env_config)) }

    assert_equal 500, status
    assert_includes body.each.to_a.join, "Email the Tech Cadre"
  ensure
    body&.close
  end

  test "a crash page that cannot be drawn falls back to the static file and is logged" do
    assert_difference -> { ErrorLog.where(error_type: "error-page-exception").count }, 1 do
      with_raising(CrashController, :show) do
        with_raising(SessionsController, :new) { get root_path }
      end
    end

    assert_response :internal_server_error
    assert_includes response.body, "This file lives in public/500.html"
  end

  test "a HEAD request that crashes gets no body" do
    with_raising(SessionsController, :new) { head root_path, headers: { "Accept" => "text/html" } }

    assert_response :internal_server_error
    assert_empty response.body
  end

  # ---- Everything else ----

  test "another status still gets its static file" do
    sign_in_as person(:active_ranger)
    with_raising(Me::DashboardController, :index, ActionController::InvalidAuthenticityToken.new) { get me_root_path }

    assert_response :unprocessable_content
    assert_includes response.body, "This file lives in public/422.html"
  end

  test "the static crash page names the Tech Cadre too" do
    assert_includes Rails.public_path.join("500.html").read, "mailto:#{EmailAddresses::TECH_CADRE}"
  end

  private

  # There is no mocking gem: the action is swapped for the test's own, then put back.
  def with_action(controller, action, body)
    original = controller.instance_method(action)
    controller.define_method(action, &body)
    yield
  ensure
    controller.define_method(action, original)
  end

  def with_raising(controller, action, error = RuntimeError.new("boom"), &)
    with_action(controller, action, -> { raise error }, &)
  end
end
