# frozen_string_literal: true

require "test_helper"

class Admin::BugReportsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  CHROME_ON_A_MAC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

  setup do
    Rails.cache.clear
    Current.reset
    BugReport.delete_all

    @admin = person(:active_ranger)
    @tech_ninja = person(:echelon_ranger)
    @reporter = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # Narrower than the other logs on purpose. This is the test that fails if the
  # gate is ever widened to match them.
  test "an admin who is not a tech ninja is turned away from the log and the purge" do
    file_report
    sign_in_as(@admin)

    get admin_bug_reports_path
    assert_redirected_to me_root_path

    delete admin_purge_bug_reports_path
    assert_redirected_to me_root_path
    assert_equal 1, BugReport.count
  end

  test "a tech ninja reads a report, with the whole of it in the detail row" do
    report = file_report(description: "The Save button does nothing.\nI pressed it twice.",
                         url: "/me/timesheet", ip: "10.42.0.5", user_agent: CHROME_ON_A_MAC)
    sign_in_as(@tech_ninja)

    get admin_bug_reports_path

    assert_response :success
    assert_select "h1", text: /Bug Reports/
    assert_select "td", text: @reporter.callsign
    assert_select "td", text: "Chrome 126 · Mac OS X 10.15.7"
    assert_select "tr#bug-report-detail-#{report.id}.hidden" do
      assert_select "div.whitespace-pre-line", text: /I pressed it twice\./
      assert_select "dd", text: "/me/timesheet"
      assert_select "dd", text: "10.42.0.5"
      assert_select "dd", text: CHROME_ON_A_MAC
    end
    assert_select "a[href=?][data-turbo-method=delete]", admin_purge_bug_reports_path
  end

  test "what a person typed is shown as text, never as markup" do
    file_report(description: "<script>alert(1)</script> broke the page")
    sign_in_as(@tech_ninja)

    get admin_bug_reports_path

    assert_response :success
    assert_select "main script", count: 0
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt; broke the page"
  end

  test "an empty log says so and offers nothing to delete" do
    sign_in_as(@tech_ninja)

    get admin_bug_reports_path

    assert_response :success
    assert_includes response.body, "No bug reports yet."
    # The sidebar links to this same address, so the verb is what tells the
    # delete button apart.
    assert_select "a[href=?][data-turbo-method=delete]", admin_purge_bug_reports_path, count: 0
  end

  test "a report with no browser recorded shows a dash" do
    file_report(user_agent: nil)
    sign_in_as(@tech_ninja)

    get admin_bug_reports_path

    assert_response :success
    # Not "Other · Other", which is what the parser makes of nothing.
    assert_select "td[data-label=Browser]", text: "-"
  end

  test "a log longer than one page says how much of it is showing" do
    now = Time.current
    BugReport.insert_all((BugReport::LIST_LIMIT + 1).times.map { |n|
      { person_id: @reporter.id, description: "Report #{n}", created_at: now }
    })
    sign_in_as(@tech_ninja)

    get admin_bug_reports_path

    assert_response :success
    assert_select "tr.table-detail-row", count: BugReport::LIST_LIMIT
    assert_includes response.body, "Showing the newest #{BugReport::LIST_LIMIT} of #{BugReport::LIST_LIMIT + 1} reports."
    # Newest first: the last one written is on the page, the first is not.
    assert_includes response.body, "Report #{BugReport::LIST_LIMIT}"
    assert_select "td", text: "Report 0", count: 0
  end

  test "a log that fits on the page does not mention a limit" do
    file_report
    sign_in_as(@tech_ninja)

    get admin_bug_reports_path

    assert_response :success
    assert_not_includes response.body, "Showing the newest"
  end

  test "purge deletes every report and records who did it" do
    file_report
    file_report(description: "Another one.")
    sign_in_as(@tech_ninja)

    assert_difference -> { ActionLog.where(event: "bug-report-purge").count }, 1 do
      delete admin_purge_bug_reports_path
    end

    assert_redirected_to admin_bug_reports_path
    assert_equal 0, BugReport.count

    audit = ActionLog.where(event: "bug-report-purge").order(:id).last
    assert_equal @tech_ninja.id, audit.person_id
    assert_equal 2, audit.data["count"]
  end

  private

  def file_report(**attributes)
    BugReport.create!({ person: @reporter, description: "Something went wrong." }.merge(attributes))
  end
end
