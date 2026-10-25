# frozen_string_literal: true

require "test_helper"

class Person::MailLogControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include ReportCardTestHelper # card_answer / assert_no_card_question

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)

    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    # Holds a role in the broad PersonConcern gate but not in this page's
    # narrowed [ADMIN, VC] gate.
    @mentor = person(:ranger_with_custom_gender)
    # No mail log or email history rows point at this person.
    @clean = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::MENTOR, "Mentor")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@mentor, Role::MENTOR)
  end

  teardown do
    Rails.cache.clear
  end

  test "admin sees the mail log, stats, and email history" do
    log = create_mail_log(subject: "Shift reminder", body: "<html><body>Hello HTML</body></html>")
    EmailHistory.create!(person_id: @target.id, email: "old.address@example.com", source_person_id: @admin.id)

    sign_in_as(@admin)
    get person_mail_log_path(@target)

    assert_response :success
    assert_select "body", text: /Shift reminder/
    assert_select "body", text: /volunteer@example.com/
    assert_select "body", text: /Last 24 Hours/
    assert_select "body", text: /Last 6 Months/
    # Below lg each message folds into a labelled card (common/mail_log/_table).
    assert_select "div.table-container.w-fit > table.responsive-table"
    assert_select "td[data-label='From / To']", text: /volunteer@example\.com/
    # The message body is not inlined — each row holds a lazy turbo frame
    # pointing at the body action.
    assert_select "turbo-frame[loading=lazy][src=?]", person_mail_log_body_path(@target, log)
    assert_no_match(/Hello HTML/, response.body)
    # Email change history row with a link to the person who made the change.
    assert_select "body", text: /old.address@example.com/
    assert_select "a[href=?]", person_path(@admin), text: @admin.callsign
  end

  test "vc sees the mail log" do
    create_mail_log(subject: "Training update")

    sign_in_as(@vc)
    get person_mail_log_path(@target)

    assert_response :success
    assert_select "body", text: /Training update/
  end

  test "person without the admin or vc role is denied" do
    sign_in_as(@mentor)

    get person_mail_log_path(@target)

    assert_redirected_to me_root_path
    assert_equal "Admin or Volunteer Coordinator role required to view the mail log.", flash[:error]
  end

  test "a bounced message is marked" do
    create_mail_log(subject: "Bounced message", did_bounce: true)

    sign_in_as(@admin)
    get person_mail_log_path(@target)

    assert_response :success
    assert_select "tr.text-error .fa-triangle-exclamation"
  end

  test "body renders an html message attribute-escaped into the sandboxed srcdoc iframe" do
    log = create_mail_log(subject: "HTML message", body: "<html><body>Hello HTML</body></html>")

    sign_in_as(@admin)
    get person_mail_log_body_path(@target, log)

    assert_response :success
    assert_select "turbo-frame[id=?] iframe[sandbox]", "mail-log-body-frame-#{log.id}"
    assert_select ".empty-state", count: 0
    assert_match(/&lt;html&gt;/, response.body)
    assert_match(/Hello HTML/, response.body)
  end

  # A sign-in link or a private message is never kept, so its row has no text
  # to frame -- the page says so instead of drawing an empty message.
  test "body of a message whose text was not kept says so instead of framing it" do
    log = create_mail_log(subject: "Ranger Clubhouse Password Reset")
    log.update_column(:body, nil)

    sign_in_as(@vc)
    get person_mail_log_body_path(@target, log)

    assert_response :success
    assert_select "turbo-frame[id=?] .empty-state", "mail-log-body-frame-#{log.id}",
                  text: "The text of this email isn't kept, so it can't be shown."
    assert_select "iframe", count: 0
  end

  test "body wraps a plain text message in an escaped pre block" do
    log = create_mail_log(subject: "Plain text", body: "Line one\nLine two")

    sign_in_as(@admin)
    get person_mail_log_body_path(@target, log)

    assert_response :success
    assert_match(/&lt;pre.*?&gt;Line one\nLine two&lt;\/pre&gt;/m, response.body)
  end

  test "body finds a message the person sent" do
    log = create_mail_log(subject: "Sent by target", person: @clean, sender_id: @target.id)

    sign_in_as(@admin)
    get person_mail_log_body_path(@target, log)

    assert_response :success
    assert_match(/Plain body/, response.body)
  end

  test "body for a message belonging to another person is not found" do
    log = create_mail_log(subject: "Not yours", person: @clean)

    sign_in_as(@admin)

    begin
      get person_mail_log_body_path(@target, log)
      assert_response :not_found
    rescue ActiveRecord::RecordNotFound
      # Expected behavior when RecordNotFound propagates instead of being rescued into a response.
    end
  end

  test "person without the admin or vc role is denied the message body" do
    log = create_mail_log(subject: "Secret")

    sign_in_as(@mentor)
    get person_mail_log_body_path(@target, log)

    assert_redirected_to me_root_path
    assert_equal "Admin or Volunteer Coordinator role required to view the mail log.", flash[:error]
  end

  test "pagination shows the next page of older messages" do
    (MailLog::PAGE_SIZE_DEFAULT + 1).times do |i|
      create_mail_log(subject: "Message #{i}", created_at: Time.current - i.minutes)
    end

    sign_in_as(@admin)
    get person_mail_log_path(@target)

    assert_response :success
    # The shared pager, above the table and below it.
    assert_select "p", text: "Page 1 of 2 · #{MailLog::PAGE_SIZE_DEFAULT + 1} messages", count: 2
    assert_select "a[href=?]", person_mail_log_path(@target, page: 2), text: "Next Page", count: 2

    get person_mail_log_path(@target, page: 2)

    assert_response :success
    assert_select "body", text: /Page 2 of 2/
    # Ordered created_at desc, so the oldest message lands on page 2.
    assert_select "body", text: /Message #{MailLog::PAGE_SIZE_DEFAULT}/
    assert_select "a[href=?]", person_mail_log_path(@target, page: 1), text: "Previous Page", count: 2
  end

  test "an invalid page parameter falls back to page 1" do
    create_mail_log(subject: "Only message")

    sign_in_as(@admin)
    get person_mail_log_path(@target, page: "abc")

    assert_response :success
    assert_select "body", text: /Only message/
  end

  test "empty states render for a person with no mail activity" do
    sign_in_as(@admin)

    get person_mail_log_path(@clean)

    assert_response :success
    assert_select "body", text: /No mail logs were found/
    assert_select "body", text: /The email address has not changed/
  end

  # The legend is about the messages, so it goes when there is none to read.
  # How far back the log goes stays: it is what explains an empty one.
  test "the card explains the icons only while there are messages" do
    legend = "What do the icons mean?"
    create_mail_log(subject: "Shift reminder")

    sign_in_as(@admin)
    get person_mail_log_path(@target)

    assert_match(/#{MailLogHelper::BOUNCED_LABEL}/, card_answer(legend))

    get person_mail_log_path(@clean)

    assert_match(/are kept/, card_answer("How far back does the log go?"))
    assert_no_card_question legend
  end

  private

  def create_mail_log(subject:, body: "Plain body", did_bounce: false, created_at: Time.current,
                      person: @target, sender_id: nil)
    MailLog.create!(
      person_id: person.id,
      sender_id: sender_id,
      from_email: "do-not-reply@burningman.org",
      to_email: "volunteer@example.com",
      message_id: "msg-#{SecureRandom.hex(8)}",
      subject: subject,
      body: body,
      did_bounce: did_bounce,
      created_at: created_at
    )
  end
end
