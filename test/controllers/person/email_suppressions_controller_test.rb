# frozen_string_literal: true

require "test_helper"

class Person::EmailSuppressionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include EmailSuppressionTestHelper
  include PersonTestFactory
  include TimesheetAdminTestHelper

  # A clause of the confirmation's SES paragraph.
  SES_SENTENCE = /only someone with access to the SES console can remove it there/

  setup do
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    [[Role::ADMIN, "Admin"], [Role::TECH_NINJA, "Tech Ninja"], [Role::VC, "VC"],
     [Role::MENTOR, "Mentor"]].each { |id, title| ensure_role(id, title) }
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "an admin clears the row, and the log names who, whose and which address" do
    admin = viewer("Admin", Role::ADMIN)
    suppress_email(@target.email, sub_type: "General", message_id: "ses-1")

    assert_difference -> { EmailSuppression.count }, -1 do
      post person_email_suppression_clear_path(@target)
    end

    assert_redirected_to person_path(@target)
    assert_equal "Cleared the bounce report for #{@target.callsign}'s email address.", flash[:success]
    log = ActionLog.find_by!(event: "email-suppression-clear")
    assert_equal admin.id, log.person_id
    assert_equal @target.id, log.target_person_id
    assert_equal @target.email, log.data["email"]
    assert_equal({ "reason" => "bounce", "sub_type" => "General", "report_count" => 1, "message_id" => "ses-1" },
                 log.data.slice("reason", "sub_type", "report_count", "message_id"))
    assert log.data["first_reported_at"].present?
    assert log.data["last_reported_at"].present?
  end

  # Tech Ninja alone opens neither page, but the route takes them.
  test "a tech ninja clears the row" do
    ninja = viewer("Ninja", Role::TECH_NINJA)
    suppress_email(@target.email, reason: EmailSuppression::COMPLAINT)

    post person_email_suppression_clear_path(@target)

    assert_not EmailSuppression.suppressed?(@target.email)
    log = ActionLog.find_by!(event: "email-suppression-clear")
    assert_equal [ninja.id, @target.id, @target.email, "complaint"],
                 [log.person_id, log.target_person_id, log.data["email"], log.data["reason"]]
    assert_match(/Cleared the spam report .* until it is also removed in the SES console\./, flash[:success])
  end

  test "the clear goes back to the page it came from" do
    viewer("Admin", Role::ADMIN)
    suppress_email(@target.email)

    post person_email_suppression_clear_path(@target),
         headers: { "Referer" => hq_shift_manage_url(@target) }

    assert_redirected_to hq_shift_manage_url(@target)
  end

  test "any other person-page role is refused, and the row stays" do
    suppress_email(@target.email)

    [Role::VC, Role::MENTOR].each do |role_id|
      viewer("Viewer#{role_id}", role_id)

      assert_no_difference -> { EmailSuppression.count } do
        post person_email_suppression_clear_path(@target)
      end
      assert_redirected_to me_root_path
    end
    assert_equal 0, ActionLog.where(event: "email-suppression-clear").count
  end

  test "the clear button shows to an admin and a tech ninja only" do
    suppress_email(@target.email)

    { [Role::ADMIN] => 1, [Role::MENTOR, Role::TECH_NINJA] => 1, [Role::VC] => 0,
      [Role::MENTOR] => 0 }.each do |roles, count|
      viewer("Viewer#{roles.join("x")}", *roles)

      get person_path(@target)

      assert_select "#email-suppression-banner", count: 1
      assert_select "#email-suppression-banner a[href='#{person_email_suppression_clear_path(@target)}']" \
                    "[data-turbo-method='post']", { count:, text: "Clear Bounce Report" },
                    "roles #{roles}"
    end
  end

  test "the confirmation names SES's list for a complaint and an OnAccountSuppressionList bounce only" do
    viewer("Admin", Role::ADMIN)
    rows = { EmailSuppression::COMPLAINT => nil, EmailSuppression::BOUNCE => EmailSuppression::ON_ACCOUNT_SUPPRESSION_LIST }

    rows.each do |reason, sub_type|
      suppress_email(@target.email, reason:, sub_type:)

      get person_path(@target)

      assert_match SES_SENTENCE, confirmation, "#{reason} #{sub_type}"
      # SES answers the next send with a bounce, so even a spam report comes back as one.
      assert_match(/the next broadcast email records it as bounced\./, confirmation, "#{reason} #{sub_type}")
      EmailSuppression.delete_all
    end

    suppress_email(@target.email, sub_type: "General")
    get person_path(@target)

    assert_match(/Clearing removes this report, and the warning goes away/, confirmation)
    assert_no_match SES_SENTENCE, confirmation
  end

  test "with no row, nothing is deleted or logged" do
    viewer("Admin", Role::ADMIN)
    suppress_email("someone-else@example.com")

    assert_no_difference [-> { EmailSuppression.count }, -> { ActionLog.where(event: "email-suppression-clear").count }] do
      post person_email_suppression_clear_path(@target)
    end

    assert_redirected_to person_path(@target)
    assert_equal "No bounce or spam report is recorded for #{@target.callsign}'s email address.", flash[:info]
  end

  private

  # A new person holding roles, signed in.
  def viewer(callsign, *roles)
    person = create_person(callsign)
    roles.each { grant_role(person, it) }
    sign_in_as(person)
    person
  end

  # The confirmation dialog the clear button carries, as its HTML.
  def confirmation
    css_select("#email-suppression-banner a[data-turbo-confirm]").first["data-turbo-confirm"]
  end
end
