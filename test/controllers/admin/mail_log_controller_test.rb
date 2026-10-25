# frozen_string_literal: true

require "test_helper"

class Admin::MailLogControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper     # card_answer

  setup do
    Rails.cache.clear
    Current.reset
    MailLog.delete_all

    @admin = person(:active_ranger)
    # The person page is open to the Volunteer Coordinator role; this one is not.
    @vc = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @recipient = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "denies access without the admin role" do
    sign_in_as(@outsider)

    get admin_mail_log_path

    assert_redirected_to me_root_path
  end

  test "denies access to the volunteer coordinator role" do
    sign_in_as(@vc)

    get admin_mail_log_path

    assert_redirected_to me_root_path
  end

  test "admin sees the log and the sending counts" do
    log = create_mail_log(subject: "Shift reminder", body: "<html><body>Hello HTML</body></html>")

    sign_in_as(@admin)
    get admin_mail_log_path

    assert_response :success
    assert_select "h1", text: /System Mail Log/
    assert_select "body", text: /Shift reminder/
    assert_select "body", text: /Last 24 Hours/
    assert_select "body", text: /Last 6 Months/
    # Below lg each message folds into a labelled card: as a table, an address
    # that cannot break pushed a phone's page sideways.
    assert_select "div.table-container.w-fit > table.responsive-table"
    assert_select "td[data-label='From / To']", text: /volunteer@example\.com/
    # The message body is not inlined — each row holds a lazy turbo frame
    # pointing at the body action.
    assert_select "turbo-frame[loading=lazy][src=?]", admin_mail_log_body_path(log)
    assert_no_match(/Hello HTML/, response.body)
  end

  test "lists messages sent to any person, not only one" do
    create_mail_log(subject: "To the auditor", person: @recipient)
    create_mail_log(subject: "To the admin", person: @admin)

    sign_in_as(@admin)
    get admin_mail_log_path

    assert_response :success
    assert_select "body", text: /To the auditor/
    assert_select "body", text: /To the admin/
  end

  test "a bounced message is marked" do
    create_mail_log(subject: "Bounced message", did_bounce: true)

    sign_in_as(@admin)
    get admin_mail_log_path

    assert_response :success
    assert_select "tr.text-error .fa-triangle-exclamation"
  end

  test "a subject carrying markup is escaped rather than rendered" do
    create_mail_log(subject: "<script>alert(1)</script>")

    sign_in_as(@admin)
    get admin_mail_log_path

    assert_response :success
    assert_no_match(%r{<script>alert\(1\)</script>}, response.body)
    assert_match(/&lt;script&gt;/, response.body)
  end

  test "filters by callsign, matching messages sent to or from that person" do
    create_mail_log(subject: "Sent to auditor", person: @recipient)
    create_mail_log(subject: "Sent by auditor", person: @admin, sender_id: @recipient.id)
    create_mail_log(subject: "Unrelated message", person: @admin)

    sign_in_as(@admin)
    get admin_mail_log_path(filter: { person_callsign: @recipient.callsign })

    assert_response :success
    assert_select "body", text: /Sent to auditor/
    assert_select "body", text: /Sent by auditor/
    assert_no_match(/Unrelated message/, response.body)
  end

  test "a callsign no one holds returns no messages rather than all of them" do
    create_mail_log(subject: "Every message")

    sign_in_as(@admin)
    get admin_mail_log_path(filter: { person_callsign: "NotARealCallsign" })

    assert_response :success
    assert_no_match(/Every message/, response.body)
    assert_select "body", text: /No messages matched/
  end

  test "searches part of either the sending or the receiving address" do
    create_mail_log(subject: "Went to the old address", to_email: "gone@oldisp.example")
    create_mail_log(subject: "Came from the list", from_email: "ranger-vc-list@example.com")
    create_mail_log(subject: "Neither one")

    sign_in_as(@admin)
    get admin_mail_log_path(filter: { email: "oldisp" })

    assert_response :success
    assert_select "body", text: /Went to the old address/
    assert_no_match(/Neither one/, response.body)

    get admin_mail_log_path(filter: { email: "ranger-vc-list" })

    assert_response :success
    assert_select "body", text: /Came from the list/
    assert_no_match(/Neither one/, response.body)
  end

  test "searches part of the subject line" do
    create_mail_log(subject: "Training sign-up confirmation")
    create_mail_log(subject: "Password reset")

    sign_in_as(@admin)
    get admin_mail_log_path(filter: { subject: "sign-up" })

    assert_response :success
    assert_select "body", text: /Training sign-up confirmation/
    assert_no_match(/Password reset/, response.body)
  end

  test "subject search finds a message whose subject lives on its broadcast" do
    broadcast = Broadcast.create!(sender_id: @admin.id, alert_id: 1, subject: "Burn night muster",
                                 email_message: "<html><body>Muster at 6</body></html>")
    create_mail_log(subject: nil, broadcast_id: broadcast.id)
    create_mail_log(subject: "Password reset")

    sign_in_as(@admin)
    get admin_mail_log_path(filter: { subject: "muster" })

    assert_response :success
    assert_select "body", text: /Burn night muster/
    assert_no_match(/Password reset/, response.body)
  end

  test "the search fields narrow together, each one excluding on its own" do
    create_mail_log(subject: "Training update", person: @recipient)
    # Each of these is ruled out by exactly one of the three fields, so dropping
    # any field from the query would let one of them through.
    create_mail_log(subject: "Training update", person: @admin)
    create_mail_log(subject: "Training update", person: @recipient, to_email: "other@example.org")
    create_mail_log(subject: "Password reset", person: @recipient)

    sign_in_as(@admin)
    get admin_mail_log_path(filter: { person_callsign: @recipient.callsign,
                                      email: "volunteer@example.com",
                                      subject: "Training" })

    assert_response :success
    assert_select "body", text: /Training update/
    assert_select "tbody tr td:nth-child(3) button", count: 1
    assert_no_match(/other@example.org/, response.body)
    assert_no_match(/Password reset/, response.body)
  end

  test "a message marked as spam is flagged" do
    create_mail_log(subject: "Complained message", did_complain: true)

    sign_in_as(@admin)
    get admin_mail_log_path

    assert_response :success
    # The legend that explains the icon is not on screen with the row, so the
    # icon says it itself: a tooltip, and words for a screen reader.
    assert_select "tr.text-warning .fa-bell[title='Marked as spam']"
    assert_select "tr.text-warning", text: /Marked as spam/
  end

  test "a filter parameter that is not a hash is ignored rather than crashing" do
    create_mail_log(subject: "Still listed")

    sign_in_as(@admin)

    get admin_mail_log_path(filter: "nonsense")
    assert_response :success
    assert_select "body", text: /Still listed/

    get admin_mail_log_path("filter[]" => "nonsense")
    assert_response :success
    assert_select "body", text: /Still listed/
  end

  test "a page number past the end lands on the last real page" do
    create_mail_log(subject: "Only message")

    sign_in_as(@admin)
    get admin_mail_log_path(filter: { page: 99_999_999_999 })

    assert_response :success
    # The rows and the label agree: no empty table under a pager claiming otherwise.
    assert_select "body", text: /Only message/
    assert_select "body", text: /Page 1 of 1/
  end

  test "a search that matches nothing shows the empty state and leaves the card its legend" do
    create_mail_log(subject: "Only message")

    sign_in_as(@admin)
    get admin_mail_log_path(filter: { subject: "nothing matches this" })

    assert_response :success
    # A search past the window finds nothing for that reason alone, so the
    # empty state says how far back the log goes.
    assert_select "body", text: /No messages matched the current search\. Only the last .+ are kept\./
    # The card sits above the search bar and describes the log, not the search.
    assert_match(/#{MailLogHelper::BOUNCED_LABEL}/, card_answer("What do the icons mean?"))
  end

  test "pagination shows the next page of older messages" do
    (MailLog::PAGE_SIZE_DEFAULT + 1).times do |i|
      create_mail_log(subject: "Message #{i}", created_at: Time.current - i.minutes)
    end

    sign_in_as(@admin)
    get admin_mail_log_path

    assert_response :success
    assert_select "body", text: /Page 1 of 2/
    assert_select "a", text: /Next Page/

    get admin_mail_log_path(filter: { page: 2 })

    assert_response :success
    assert_select "body", text: /Page 2 of 2/
    # Ordered newest first, so the oldest message lands on page 2.
    assert_select "body", text: /Message #{MailLog::PAGE_SIZE_DEFAULT}/
    assert_select "a", text: /Previous Page/
  end

  test "pager links carry the search onto the next page" do
    (MailLog::PAGE_SIZE_DEFAULT + 1).times do |i|
      create_mail_log(subject: "Reminder #{i}", created_at: Time.current - i.minutes)
    end

    sign_in_as(@admin)
    get admin_mail_log_path(filter: { subject: "Reminder" })

    assert_response :success
    assert_select "a[href=?]", admin_mail_log_path(filter: { subject: "Reminder", page: 2 })
  end

  test "body renders the message inside a sandboxed frame" do
    log = create_mail_log(subject: "HTML message", body: "<html><body>Hello HTML</body></html>")

    sign_in_as(@admin)
    get admin_mail_log_body_path(log)

    assert_response :success
    assert_select "turbo-frame[id=?] iframe[sandbox]", "mail-log-body-frame-#{log.id}"
    assert_select ".empty-state", count: 0
    assert_match(/&lt;html&gt;/, response.body)
    assert_match(/Hello HTML/, response.body)
  end

  test "body of a message whose text was not kept says so instead of framing it" do
    log = create_mail_log(subject: "[Clubhouse Message] Shift swap")
    log.update_column(:body, nil)

    sign_in_as(@admin)
    get admin_mail_log_body_path(log)

    assert_response :success
    assert_select "turbo-frame[id=?] .empty-state", "mail-log-body-frame-#{log.id}",
                  text: "The text of this email isn't kept, so it can't be shown."
    assert_select "iframe", count: 0
  end

  test "body reaches any message, whoever it was sent to" do
    log = create_mail_log(subject: "Someone else's message", person: @recipient)

    sign_in_as(@admin)
    get admin_mail_log_body_path(log)

    assert_response :success
    assert_match(/Plain body/, response.body)
  end

  test "denies the message body without the admin role" do
    log = create_mail_log(subject: "Secret")

    sign_in_as(@vc)
    get admin_mail_log_body_path(log)

    assert_redirected_to me_root_path
  end

  private

  def create_mail_log(subject:, body: "Plain body", did_bounce: false, did_complain: false,
                      created_at: Time.current, person: nil, sender_id: nil,
                      to_email: "volunteer@example.com",
                      from_email: "do-not-reply@burningman.org", broadcast_id: nil)
    MailLog.create!(
      person_id: (person || @recipient).id,
      sender_id: sender_id,
      broadcast_id: broadcast_id,
      from_email: from_email,
      to_email: to_email,
      message_id: "msg-#{SecureRandom.hex(8)}",
      subject: subject,
      body: body,
      did_bounce: did_bounce,
      did_complain: did_complain,
      created_at: created_at
    )
  end
end
