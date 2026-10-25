# frozen_string_literal: true

require "test_helper"

class RequestLoggerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  # A response body of the shape ActionDispatch hands back: enumerable, and
  # able to give up its whole content at once.
  class StubBody
    def initialize(text)
      @text = text
    end

    def body
      @text
    end

    def each
      yield @text
    end
  end

  # A response backed by a file on disk: Rack serves it by path rather than by
  # reading it, and reading it here would be the bug.
  class FileishBody
    def to_path
      "/tmp/export.csv"
    end

    def body
      raise "the body must not be read"
    end

    def each
      yield ""
    end
  end

  setup do
    Rails.cache.clear
    Current.reset
    RequestLog.delete_all
    ErrorLog.delete_all

    enable_recording(true)

    @person = person(:active_ranger)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def enable_recording(enabled)
    Setting.where(name: Setting::REQUEST_LOG_ENABLED).delete_all
    Setting.create!(name: Setting::REQUEST_LOG_ENABLED, value: enabled.to_s)
  end

  # Runs one request through the middleware alone, with a stubbed application
  # underneath it.
  def run_request(path, status: 200, method: "GET", body: "ok", headers: {}, **env_options)
    app = ->(_env) { [status, headers, StubBody.new(body)] }
    env = Rack::MockRequest.env_for(path, method: method, **env_options)

    RequestLogger.new(app).call(env)
  end

  # Makes recording fail the way a database problem would, then puts it back.
  def with_failing_record
    original = RequestLog.method(:record)
    RequestLog.define_singleton_method(:record) { |**| raise ActiveRecord::StatementInvalid, "no room" }
    yield
  ensure
    RequestLog.define_singleton_method(:record, original)
  end

  def run_failing_request(exception)
    app = ->(_env) { raise exception }

    RequestLogger.new(app).call(Rack::MockRequest.env_for("/me/dashboard"))
  end

  test "records an answered request" do
    run_request("/me/dashboard", status: 200, body: "hello")

    log = RequestLog.last

    assert_equal "me/dashboard", log.url
    assert_equal 200, log.status
    assert_equal "GET", log.method
    assert_equal 5, log.response_size
    assert log.completion_time >= 0
  end

  test "prefers the content length the response declares" do
    run_request("/me/dashboard", headers: { "content-length" => "1234" })

    assert_equal 1234, RequestLog.last.response_size
  end

  test "records the signed-in person" do
    Current.person = @person

    run_request("/me/dashboard")

    assert_equal @person.id, RequestLog.last.person_id
  end

  test "stores the root path as something readable" do
    run_request("/")

    assert_equal "/", RequestLog.last.url
  end

  test "leaves the query string out of the recorded path" do
    run_request("/me/dashboard?token=secret")

    assert_equal "me/dashboard", RequestLog.last.url
    assert_no_match "secret", RequestLog.last.url
  end

  test "keeps what was sent and returned only for a rejected request" do
    run_request("/me/profile", method: "POST", status: 422, body: "<p>Try again</p>",
                params: { "callsign" => "Bumblebee", "password" => "hunter2" })

    log = RequestLog.last

    assert_match "Bumblebee", log.request_payload
    assert_no_match(/hunter2/, log.request_payload)
    assert_equal "<p>Try again</p>", log.response_payload
  end

  test "keeps no payloads for a request that succeeded" do
    run_request("/me/profile", method: "POST", status: 200,
                params: { "callsign" => "Bumblebee" })

    log = RequestLog.last

    assert_nil log.request_payload
    assert_nil log.response_payload
  end

  test "records a failure as a failure and lets it carry on" do
    assert_raises(ArgumentError) { run_failing_request(ArgumentError.new("boom")) }

    assert_equal 500, RequestLog.last.status
  end

  test "records the status the reader will actually be shown, not always 500" do
    assert_raises(ActiveRecord::RecordNotFound) { run_failing_request(ActiveRecord::RecordNotFound.new("nope")) }

    assert_equal 404, RequestLog.last.status
  end

  test "records a stale form token as the rejection it becomes" do
    assert_raises(ActionController::InvalidAuthenticityToken) do
      run_failing_request(ActionController::InvalidAuthenticityToken.new)
    end

    assert_equal 422, RequestLog.last.status
  end

  test "keeps the name of an uploaded file rather than the object behind it" do
    upload = ActionDispatch::Http::UploadedFile.new(tempfile: Tempfile.new("x"), filename: "headshot.jpg",
                                                    type: "image/jpeg")
    app = ->(_env) { [422, {}, StubBody.new("nope")] }
    env = Rack::MockRequest.env_for("/me/photo", method: "POST")
    env["action_dispatch.request.request_parameters"] = { "person" => { "photo" => upload } }

    RequestLogger.new(app).call(env)

    assert_equal '{"person":{"photo":"headshot.jpg"}}', RequestLog.last.request_payload
  end

  test "does not read a download into memory just to measure it" do
    app = ->(_env) { [200, {}, FileishBody.new] }

    RequestLogger.new(app).call(Rack::MockRequest.env_for("/export.csv"))

    assert_equal 0, RequestLog.last.response_size
  end

  test "skips the health check and the socket" do
    run_request("/up")
    run_request("/cable")

    assert_equal 0, RequestLog.count
  end

  test "skips a preflight request" do
    run_request("/me/dashboard", method: "OPTIONS")

    assert_equal 0, RequestLog.count
  end

  # The error log is as much the point of this test as the other two counts.
  # With recording off the middleware used to raise on every single request and
  # write the crash there, which left the two counts below at zero for the
  # wrong reason.
  test "records nothing while recording is switched off" do
    enable_recording(false)

    status, = run_request("/me/dashboard")

    assert_equal 200, status
    assert_equal 0, RequestLog.count
    assert_equal 0, ActionLog.count
    assert_equal 0, ErrorLog.count
  end

  test "answers the request even when the log cannot be written" do
    with_failing_record do
      status, = run_request("/me/dashboard")

      assert_equal 200, status
    end

    assert_equal 0, RequestLog.count
  end

  test "records the page as an action of the signed-in person" do
    Current.person = @person

    run_request("/me/dashboard")

    log = ActionLog.last

    assert_equal "page-visit", log.event
    assert_equal "me/dashboard", log.message
    assert_equal @person.id, log.person_id
    assert_nil log.target_person_id
  end

  test "records whose page it was" do
    run_request("/person/#{@person.id}/timesheets")

    assert_equal @person.id, ActionLog.last.target_person_id

    run_request("/hq/#{@person.id}")

    assert_equal @person.id, ActionLog.last.target_person_id

    run_request("/person/bulk-lookup")

    assert_nil ActionLog.last.target_person_id
  end

  # An Active Storage redirect is a page's images arriving, not a second visit
  # to the page. It is still a request the Clubhouse answered, so the request
  # log keeps it.
  test "does not count Rails' own paths as pages visited" do
    run_request("/rails/active_storage/blobs/redirect/abcd1234/headshot.jpg")

    assert_equal "rails/active_storage/blobs/redirect/abcd1234/headshot.jpg", RequestLog.last.url
    assert_equal 0, ActionLog.where(event: "page-visit").count
  end

  test "records a real request end to end" do
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@person, Role::ADMIN)
    sign_in_as(@person)

    get admin_request_logs_path

    assert_response :success

    log = RequestLog.last

    assert_equal "admin/request-logs", log.url
    assert_equal @person.id, log.person_id
    assert_equal 200, log.status
    assert_equal "GET", log.method
    assert log.response_size.positive?
  end

  # The controller notes where a request came from only once the request gets
  # that far, and most of what a crawler asks for never does: a signed-out
  # visitor is sent to the sign-in page first, a path nothing answers reaches
  # no controller, and an outdated browser is turned away at the door.
  test "records where a page was asked from even when no controller got that far" do
    crawler = {
      "X-Forwarded-For" => "203.0.113.7",
      "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " \
                      "Chrome/91.0.4472.124 Safari/537.36"
    }

    get "/me", headers: crawler
    assert_response :redirect

    get "/no-such-page", headers: crawler
    assert_response :not_found

    get "/", headers: crawler
    assert_response :not_acceptable

    visits = ActionLog.where(event: "page-visit").order(:id)

    assert_equal ["me", "no-such-page", "/"], visits.map(&:message)
    visits.each do |visit|
      assert_equal "203.0.113.7", visit.ip, visit.message
      assert_equal crawler["User-Agent"], visit.user_agent, visit.message
    end
  end
end
