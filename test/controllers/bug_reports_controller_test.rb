# frozen_string_literal: true

require "test_helper"

class BugReportsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Current.reset
    BugReport.delete_all

    @reporter = person(:active_ranger)
  end

  teardown do
    Current.reset
  end

  test "signed out, the dialog and the report both go to the sign-in page" do
    get new_bug_report_path
    assert_redirected_to root_path

    assert_no_difference -> { BugReport.count } do
      post bug_reports_path, params: { bug_report: { description: "Nobody is signed in." } }
    end
    assert_redirected_to root_path
  end

  test "the dialog opens inside the modal frame with the field focused" do
    sign_in_as(@reporter)

    get new_bug_report_path

    assert_response :success
    assert_select "turbo-frame#modal dialog#bug-report-dialog" do
      assert_select "form[action=?]", bug_reports_path
      assert_select "textarea[name='bug_report[description]'][autofocus][required]"
      assert_select "input[type=submit][value='Send Bug Report']"
    end
  end

  test "a report records the person, the page without its query string, the address, and the browser" do
    sign_in_as(@reporter)

    assert_difference -> { BugReport.count }, 1 do
      post bug_reports_path,
           params: { bug_report: { description: "The Save button does nothing." } },
           headers: { "HTTP_REFERER" => "http://www.example.com/me/timesheet?token=secret",
                      "HTTP_USER_AGENT" => "Mozilla/5.0 #{"x" * 400}" }
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "Bug report sent"

    report = BugReport.last
    assert_equal "The Save button does nothing.", report.description
    assert_equal @reporter.id, report.person_id
    assert_equal "/me/timesheet", report.url
    assert_equal "127.0.0.1", report.ip
    assert_equal BugReport::STRING_LIMIT, report.user_agent.length
    assert report.user_agent.start_with?("Mozilla/5.0 x")
    assert_in_delta Time.current, report.created_at, 1.minute
  end

  test "a report filed with no referer still saves" do
    sign_in_as(@reporter)

    assert_difference -> { BugReport.count }, 1 do
      post bug_reports_path, params: { bug_report: { description: "No referer came with this." } }
    end

    assert_nil BugReport.last.url
  end

  test "a blank report is refused and the dialog comes back saying why" do
    sign_in_as(@reporter)

    assert_no_difference -> { BugReport.count } do
      post bug_reports_path, params: { bug_report: { description: "   " } }
    end

    assert_response :unprocessable_entity
    assert_select "turbo-frame#modal dialog#bug-report-dialog", text: /Please describe what went wrong\./
  end

  test "a report longer than the limit is refused" do
    sign_in_as(@reporter)

    assert_no_difference -> { BugReport.count } do
      post bug_reports_path, params: { bug_report: { description: "x" * (BugReport::DESCRIPTION_LIMIT + 1) } }
    end

    assert_response :unprocessable_entity
    assert_select "dialog#bug-report-dialog", text: /must be 5,000 characters or fewer/
  end
end
