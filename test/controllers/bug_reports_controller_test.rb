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

  test "the dialog opens inside the modal frame asking bug or feature request" do
    sign_in_as(@reporter)

    get new_bug_report_path

    assert_response :success
    assert_select "turbo-frame#modal dialog#bug-report-dialog" do
      assert_select "a[href=?][autofocus]", new_bug_report_path(kind: "bug"), text: "Report a Bug"
      assert_select "a[href=?]", new_bug_report_path(kind: "feature"), text: "Request a Feature"
      assert_select "textarea", count: 0
    end
  end

  test "a feature request is pointed at the managing cadre and the Tech Cadre" do
    sign_in_as(@reporter)

    get new_bug_report_path(kind: "feature")

    assert_response :success
    assert_select "turbo-frame#modal dialog#bug-report-dialog", text: /cadre that manages/ do
      assert_select "a[href=?][data-turbo-frame=_top]", me_directory_path, text: "Cadre Directory"
      assert_select "a[href=?]", "mailto:#{EmailAddresses::TECH_CADRE}", text: EmailAddresses::TECH_CADRE
      assert_select "textarea", count: 0
    end
  end

  test "an unknown kind asks the question again" do
    sign_in_as(@reporter)

    get new_bug_report_path(kind: "other")

    assert_response :success
    assert_select "dialog#bug-report-dialog a[href=?]", new_bug_report_path(kind: "bug")
    assert_select "dialog#bug-report-dialog a[href=?]", new_bug_report_path(kind: "feature")
  end

  test "a bug opens the form with the field focused" do
    sign_in_as(@reporter)

    get new_bug_report_path(kind: "bug")

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
    assert_equal BugReport.columns_hash["user_agent"].limit, report.user_agent.length
    assert report.user_agent.start_with?("Mozilla/5.0 x")
    assert_in_delta Time.current, report.created_at, 1.minute
  end

  # Queued, so the job that sends it has nobody signed in: the reporter
  # travels with it, for the mail log.
  test "a report is emailed to the Tech Cadre in the reporter's name" do
    sign_in_as(@reporter)

    assert_enqueued_email_with BugReportMailer, :notify,
                               params: { sender_id: @reporter.id },
                               args: ->(args) {
                                 args.first[:callsign] == @reporter.callsign &&
                                   args.first[:description] == "The Save button does nothing."
                               } do
      post bug_reports_path, params: { bug_report: { description: "The Save button does nothing." } }
    end
  end

  # Review finding: a mail queue that refused the email turned a saved report
  # into an error page, and the person filed it again.
  test "a report the mail queue cannot take is still saved and the dialog still closes" do
    sign_in_as(@reporter)
    original = BugReportMailer.method(:with)
    BugReportMailer.define_singleton_method(:with) { |**| raise ActiveRecord::ConnectionTimeoutError, "the queue did not answer" }

    assert_difference -> { BugReport.count }, 1 do
      post bug_reports_path, params: { bug_report: { description: "The Save button does nothing." } }
    end

    assert_response :success
    assert_includes response.body, "Bug report sent"
  ensure
    BugReportMailer.define_singleton_method(:with, original)
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
    assert_select "dialog#bug-report-dialog textarea[name='bug_report[description]']"
  end

  test "a report longer than the limit is refused" do
    sign_in_as(@reporter)

    assert_no_difference -> { BugReport.count } do
      post bug_reports_path, params: { bug_report: { description: "x" * (BugReport::DESCRIPTION_LIMIT + 1) } }
    end

    assert_response :unprocessable_entity
    assert_select "dialog#bug-report-dialog", text: /must be 5,000 characters or fewer/
    assert_select "dialog#bug-report-dialog textarea[name='bug_report[description]']"
  end
end
