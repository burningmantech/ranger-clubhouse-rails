# frozen_string_literal: true

require "test_helper"

class Communication::RbsHistoryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include RbsTestHelper
  include SesTestHelper

  setup do
    Rails.cache.clear
    Current.reset
    ActionMailer::Base.deliveries.clear
    ensure_rbs_roles

    @admin = person(:active_ranger)
    @tech = person(:echelon_ranger)
    @megaphone = person(:retired_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech, Role::TECH_NINJA)
    grant_role(@megaphone, Role::MEGAPHONE)

    @listener = rbs_person("Listener")
    @broadcast = rbs_broadcast(sender: @admin, person: @listener)
    @failed = rbs_broadcast(sender: @admin, person: @listener, failed: true)
    @notification = rbs_broadcast(sender: @admin, alert_id: Alert::CLUBHOUSE_NOTIFY_ON_PLAYA,
                                  person: @listener)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ==========================================================================
  # Access
  # ==========================================================================

  test "a Tech Ninja may read the records" do
    sign_in_as(@tech)

    get communication_rbs_history_path

    assert_response :success
  end

  test "a Megaphone role alone may not read the records" do
    sign_in_as(@megaphone)

    get communication_rbs_history_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Tech Ninja role required to read the broadcast records.", flash[:error]
  end

  # ==========================================================================
  # The list
  # ==========================================================================

  test "the list starts on the broadcasts and leaves out the message alerts" do
    get communication_rbs_history_path

    assert_response :success
    assert_select "a[href=?]", communication_rbs_history_broadcast_path(@broadcast)
    assert_select "a[href=?]", communication_rbs_history_broadcast_path(@notification), false
  end

  test "the message alerts can be asked for" do
    get communication_rbs_history_path(kind: Broadcast::KIND_NOTIFICATION)

    assert_select "a[href=?]", communication_rbs_history_broadcast_path(@notification)
    assert_select "a[href=?]", communication_rbs_history_broadcast_path(@broadcast), false
  end

  test "everything can be asked for at once" do
    get communication_rbs_history_path(kind: "all")

    assert_select "a[href=?]", communication_rbs_history_broadcast_path(@notification)
    assert_select "a[href=?]", communication_rbs_history_broadcast_path(@broadcast)
  end

  test "the list can be narrowed to what failed" do
    get communication_rbs_history_path(delivery: "failed")

    assert_select "a[href=?]", communication_rbs_history_broadcast_path(@failed)
    assert_select "a[href=?]", communication_rbs_history_broadcast_path(@broadcast), false
  end

  test "a filter the page does not apply narrows nothing rather than failing" do
    get communication_rbs_history_path(kind: "<script>", delivery: "zzz", alert_id: ["1"])

    assert_response :success
  end

  test "another year has its own records" do
    get communication_rbs_history_path(year: Current.year - 1)

    assert_response :success
    assert_select "a[href=?]", communication_rbs_history_broadcast_path(@broadcast), false
  end

  # ==========================================================================
  # One broadcast
  # ==========================================================================

  test "a broadcast shows its message and who it reached" do
    get communication_rbs_history_broadcast_path(@broadcast)

    assert_response :success
    assert_match @broadcast.sms_message, response.body
    assert_match @listener.callsign, response.body
  end

  test "an email that did not go shows SES's reason" do
    BroadcastMessage.create!(broadcast_id: @broadcast.id, person_id: @listener.id, address_type: "email",
                             address: @listener.email, direction: "outbound", status: "message-rejected")

    get communication_rbs_history_broadcast_path(@broadcast)

    assert_select ".text-error", text: /Rejected by SES/
  end

  # Never sent: the address bounced for good or reported spam. A reason, like
  # an opt-out, and not a failure.
  test "an email never sent to an address that bounced or was reported as spam says so, and is no failure" do
    @broadcast.update!(sent_email: true)
    BroadcastMessage.create!(broadcast_id: @broadcast.id, person_id: @listener.id, address_type: "email",
                             address: @listener.email, direction: "outbound", status: Rbs::EMAIL_STATUS_SUPPRESSED)

    get communication_rbs_history_broadcast_path(@broadcast)

    assert_select "td .text-stone-subtle", text: "bounce or spam report on file"
    assert_no_match(/opted out/, response.body)
    # main: the navbar mega menu carries hidden error callouts of its own
    assert_select "main .box-error", count: 0
    assert_select "[class~=?]", "bg-success/10", text: /\A\s*0\s*Failed\s*\z/
    assert_select "a[href=?]", communication_rbs_retry_history_broadcast_path(@broadcast), false
  end

  # The email send records whom it skipped with their own address. A blank one
  # is no address on file, as the review page said, whitespace-only included:
  # an address stored before normalizes :email keeps its spaces. Any other skip
  # is an opt-out.
  test "an email skipped for no address on file says so, and one skipped for an opt-out says that" do
    @broadcast.update!(sent_email: true)
    foxtrot = rbs_person("Foxtrot")
    [[@listener, ""], [rbs_person("Echo"), " "], [foxtrot, foxtrot.email]].each do |person, address|
      BroadcastMessage.create!(broadcast_id: @broadcast.id, person_id: person.id, address_type: "email",
                               address:, direction: "outbound", status: Rbs::EMAIL_STATUS_NO_CONTACT)
    end

    get communication_rbs_history_broadcast_path(@broadcast)

    assert_select "td .text-stone-subtle", text: "no address", count: 2
    assert_select "td .text-stone-subtle", text: "opted out", count: 1
  end

  # ==========================================================================
  # Bounced emails
  # ==========================================================================

  # An email SES took and has since reported bounced.
  def bounced_email(person)
    BroadcastMessage.create!(broadcast_id: @broadcast.id, person_id: person.id, address_type: "email",
                             address: person.email, direction: "outbound", status: Broadcast::STATUS_BOUNCED)
  end

  test "a bounced email shows as bounced, and the Bounced stat counts it" do
    bounced_email(@listener)
    bounced_email(rbs_person("Echo"))

    get communication_rbs_history_broadcast_path(@broadcast)

    assert_select "td .text-error", text: /Bounced/, count: 2
    assert_select "[class~=?]", "bg-error/10", text: /\A\s*2\s*Bounced\s*\z/
  end

  test "the Bounced stat is plain while nothing has bounced" do
    get communication_rbs_history_broadcast_path(@broadcast)

    assert_select "[class~=?]", "bg-base-100", text: /\A\s*0\s*Bounced\s*\z/
    assert_select "[class~=?]", "bg-error/10", text: /Bounced/, count: 0
  end

  # A bounce is not a failure: the email went, and a Retry could not make it
  # arrive.
  test "a broadcast whose only problem is a bounce reads as delivered, with nothing to retry" do
    bounced_email(@listener)

    get communication_rbs_history_broadcast_path(@broadcast)

    # main: the navbar mega menu carries hidden error callouts of its own
    assert_select "main .box-error", count: 0
    assert_select "[class~=?]", "bg-success/10", text: /\A\s*0\s*Failed\s*\z/

    get communication_rbs_history_path

    assert_select "tr:has(a[href=?])", communication_rbs_history_broadcast_path(@broadcast), text: /Delivered/

    post communication_rbs_retry_history_broadcast_path(@broadcast)

    assert_redirected_to communication_rbs_history_broadcast_path(@broadcast)
    assert_equal "Nothing in that broadcast can be sent again.", flash[:info]
    assert_no_enqueued_jobs only: RbsRetryEmailJob
  end

  test "a broadcast that does not exist goes back to the list" do
    get communication_rbs_history_broadcast_path(0)

    assert_redirected_to communication_rbs_history_path
    assert_equal "That broadcast could not be found.", flash[:error]
  end

  # ==========================================================================
  # The stat row
  # ==========================================================================

  # One email of a broadcast, and what became of it.
  def recorded_email(person, status, broadcast: @broadcast)
    BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: person.id, address_type: "email",
                             address: person.email, direction: "outbound", status:)
  end

  # Emails counts what the send tried, failures and bounces included, as Texts
  # does. A person it skipped is no email.
  test "the Emails stat counts every email the send tried, and none it skipped" do
    @broadcast.update!(sent_email: true, email_failed: 1, recipient_count: 5)
    recorded_email(@listener, Broadcast::STATUS_SENT)
    recorded_email(rbs_person("Echo"), Broadcast::STATUS_BOUNCED)
    recorded_email(rbs_person("Foxtrot"), Broadcast::STATUS_SERVICE_FAIL)
    recorded_email(rbs_person("Golf"), Rbs::EMAIL_STATUS_NO_CONTACT)
    recorded_email(rbs_person("Hotel"), Rbs::EMAIL_STATUS_SUPPRESSED)

    get communication_rbs_history_broadcast_path(@broadcast)

    assert_select "[class~=?]", "bg-base-100", text: /\A\s*3\s*Emails\s*\z/
    assert_select "[class~=?]", "bg-base-100", text: /\A\s*1\s*Texts\s*\z/
    assert_select "[class~=?]", "bg-error/10", text: /\A\s*1\s*Failed\s*\z/
    assert_select "[class~=?]", "bg-error/10", text: /\A\s*1\s*Bounced\s*\z/
  end

  test "the Texts stat counts a text that failed" do
    echo = rbs_person("Echo")
    BroadcastMessage.create!(broadcast_id: @broadcast.id, person_id: echo.id, address_type: "sms",
                             address: echo.sms_number, direction: "outbound", status: Broadcast::STATUS_SERVICE_FAIL)

    get communication_rbs_history_broadcast_path(@broadcast)

    assert_select "[class~=?]", "bg-base-100", text: /\A\s*2\s*Texts\s*\z/
  end

  # A dash tells a channel not used from one used with nothing tried yet.
  test "a channel the broadcast didn't use shows a dash" do
    get communication_rbs_history_broadcast_path(@broadcast)

    assert_select "[class~=?]", "bg-base-100", text: /\A\s*1\s*Texts\s*\z/
    assert_select "[class~=?]", "bg-base-100", text: /\A\s*—\s*Emails\s*\z/

    emailed = rbs_broadcast(sender: @admin)
    emailed.update!(sent_sms: false, sent_email: true)
    recorded_email(@listener, Broadcast::STATUS_SENT, broadcast: emailed)

    get communication_rbs_history_broadcast_path(emailed)

    assert_select "[class~=?]", "bg-base-100", text: /\A\s*—\s*Texts\s*\z/
    assert_select "[class~=?]", "bg-base-100", text: /\A\s*1\s*Emails\s*\z/
  end

  # The table stops at RECIPIENT_LIMIT; the stats don't. The made-up people
  # start above every real one, so none of them is a fixture.
  test "the Texts and Emails stats count everyone, past the people the table lists" do
    broadcast = rbs_broadcast(sender: @admin)
    broadcast.update!(sent_email: true, recipient_count: 251)
    first_id = Person.maximum(:id) + 1
    rows = (Broadcast::RECIPIENT_LIMIT + 1).times.flat_map do |index|
      %w[sms email].map do |address_type|
        { broadcast_id: broadcast.id, person_id: first_id + index, address_type:, address: "#{address_type}-#{index}",
          direction: "outbound", status: Broadcast::STATUS_SENT }
      end
    end
    BroadcastMessage.insert_all!(rows)

    get communication_rbs_history_broadcast_path(broadcast)

    assert_select "[class~=?]", "bg-base-100", text: /\A\s*251\s*People\s*\z/
    assert_select "[class~=?]", "bg-base-100", text: /\A\s*251\s*Texts\s*\z/
    assert_select "[class~=?]", "bg-base-100", text: /\A\s*251\s*Emails\s*\z/
  end

  # The fixtures hold broadcast email: Wants' copy is recorded sent with no
  # call to SES, and OptedOut's no-contact.
  test "the Emails stat matches the emails the results page said were queued" do
    position = positions(:ood_position)
    rbs_holder("Wants", position)
    opted_out = rbs_holder("OptedOut", position)
    PersonAlert.create!(person_id: opted_out.id, alert_id: Alert::SHIFT_MUSTER, use_sms: true, use_email: false)

    with_ses do |calls|
      perform_enqueued_jobs do
        post communication_rbs_broadcasts_path(Broadcast::TYPE_POSITION), params: rbs_position_params(position)
      end

      assert_empty calls
    end

    assert_select "[class~=?]", "bg-success/10", text: /\A\s*1\s*Emails Queued\s*\z/

    get communication_rbs_history_broadcast_path(Broadcast.last)

    assert_select "[class~=?]", "bg-base-100", text: /\A\s*2\s*People\s*\z/
    assert_select "[class~=?]", "bg-base-100", text: /\A\s*2\s*Texts\s*\z/
    assert_select "[class~=?]", "bg-base-100", text: /\A\s*1\s*Emails\s*\z/
  end

  # ==========================================================================
  # Sending the failures again
  # ==========================================================================

  test "an admin is offered the retry on a broadcast that failed" do
    get communication_rbs_history_broadcast_path(@failed)

    assert_select "a[href=?]", communication_rbs_retry_history_broadcast_path(@failed)
  end

  test "a Tech Ninja is not offered the retry" do
    sign_in_as(@tech)

    get communication_rbs_history_broadcast_path(@failed)

    assert_response :success
    assert_select "a[href=?]", communication_rbs_retry_history_broadcast_path(@failed), false
  end

  test "a Tech Ninja may not retry a broadcast" do
    sign_in_as(@tech)

    post communication_rbs_retry_history_broadcast_path(@failed)

    assert_redirected_to communication_rbs_history_path
    assert_equal "Only an Admin may send a broadcast's failed messages again.", flash[:error]
  end

  test "retrying sends the failed messages again and reports what happened" do
    post communication_rbs_retry_history_broadcast_path(@failed)

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_equal 0, @failed.reload.sms_failed
    assert_equal @admin.id, @failed.retry_person_id
    assert_not_nil @failed.retry_at
  end

  # The text sandbox stays on: this broadcast's failure is a text.
  test "the retried page says where emails go while a test address is set" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")

    post communication_rbs_retry_history_broadcast_path(@failed)

    assert_response :unprocessable_entity
    assert_includes response.body, "<strong>test+?@example.com</strong>"
  end

  test "retrying a broadcast that did not fail changes nothing" do
    post communication_rbs_retry_history_broadcast_path(@broadcast)

    assert_redirected_to communication_rbs_history_broadcast_path(@broadcast)
    assert_equal "Nothing in that broadcast can be sent again.", flash[:info]
    assert_nil @broadcast.reload.retry_at
  end

  # Emails SES may already have sent, and emails to an invalid address.
  def stuck_emails(*statuses)
    broadcast = rbs_broadcast(sender: @admin)
    statuses.each_with_index do |status, index|
      BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: rbs_person("Stuck#{index}").id,
                               address_type: "email", address: "stuck#{index}@example.com",
                               direction: "outbound", status:)
    end
    broadcast.update!(sent_email: true, email_failed: statuses.size)
    broadcast
  end

  test "a broadcast whose failures cannot go again shows them failed, with no Retry" do
    stuck = stuck_emails(Broadcast::STATUS_INVALID_PARAMETER, Broadcast::STATUS_SEND_UNCONFIRMED)

    get communication_rbs_history_broadcast_path(stuck)

    assert_select ".box-error",
                  text: /2 emails\s+could not be sent\.\s+They can.t be sent again\. Twilio or SES may already have sent them,/
    assert_select "[class~=?]", "bg-error/10", text: /2\s*Failed/
    assert_select "a[href=?]", communication_rbs_retry_history_broadcast_path(stuck), false
  end

  test "retrying a broadcast whose failures cannot go again sends nothing" do
    stuck = stuck_emails(Broadcast::STATUS_SEND_UNCONFIRMED)

    post communication_rbs_retry_history_broadcast_path(stuck)

    assert_redirected_to communication_rbs_history_broadcast_path(stuck)
    assert_equal "Nothing in that broadcast can be sent again.", flash[:info]
    assert_nil stuck.reload.retry_at
    assert_no_enqueued_jobs only: RbsRetryEmailJob
  end

  test "the Retry counts only the failures that can go again" do
    mixed = stuck_emails(Broadcast::STATUS_INVALID_PARAMETER, "account-throttled", Broadcast::STATUS_SERVICE_FAIL)

    get communication_rbs_history_broadcast_path(mixed)

    assert_select ".box-error",
                  text: /1 message can.t be sent again\..*reaches only the other 2 messages\s+that failed;/m
    assert_select "a[href=?]", communication_rbs_retry_history_broadcast_path(mixed)
    assert_includes response.body, "Only the 2 messages that failed and can go again will be sent."
  end

  # The stored count is recounted only once a retry is done; the rows move as
  # each batch goes.
  test "an email a running retry has just sent is never called one that can't go again" do
    running = stuck_emails(Broadcast::STATUS_SERVICE_FAIL, Broadcast::STATUS_SENT, Broadcast::STATUS_SENT)
    running.update!(email_failed: 3)

    get communication_rbs_history_broadcast_path(running)

    assert_select ".box-error", text: /reaches only the 1 message\s+that failed;/
    assert_select ".box-error", text: /can.t be sent again/, count: 0
    assert_includes response.body, "Only the 1 message that failed and can go again will be sent."
  end

  # A failure stays one when its person can no longer be messaged that way,
  # though no Retry sends it.
  test "a broadcast whose only failure is to someone who may no longer be messaged has no Retry" do
    gone = rbs_broadcast(sender: @admin, person: rbs_person("Gone", status: Person::DISMISSED), failed: true)

    get communication_rbs_history_broadcast_path(gone)

    assert_select ".box-error", text: /1 text message\s+could not be sent\.\s+It can.t be sent again\./
    assert_select "a[href=?]", communication_rbs_retry_history_broadcast_path(gone), false

    post communication_rbs_retry_history_broadcast_path(gone)

    assert_redirected_to communication_rbs_history_broadcast_path(gone)
    assert_equal "Nothing in that broadcast can be sent again.", flash[:info]
    assert_nil gone.reload.retry_at
  end

  # A text to a Ranger who has since sent STOP, and an email that can go again.
  def stopped_and_retryable
    stopped = rbs_person("Stopped")
    stopped.update_columns(sms_stopped: true)
    broadcast = rbs_broadcast(sender: @admin, person: stopped, failed: true)
    BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: rbs_person("Mailed").id, address_type: "email",
                             address: "mailed@example.com", direction: "outbound",
                             status: Broadcast::STATUS_SERVICE_FAIL)
    broadcast.update!(sent_email: true, email_failed: 1)
    broadcast
  end

  test "the Retry counts only the messages that can still go, and the callout the rest" do
    mixed = stopped_and_retryable

    get communication_rbs_history_broadcast_path(mixed)

    assert_select ".box-error",
                  text: /1 text message and 1 email\s+could not be sent\.\s+1 message can.t be sent again\./
    assert_select ".box-error", text: /reaches only the other 1 message\s+that failed;/
    assert_includes response.body, "Only the 1 message that failed and can go again will be sent."
    assert_equal BroadcastMessage.where(broadcast_id: mixed.id, status: Broadcast::FAILURE_STATUSES).count,
                 mixed.failed_messages.count + mixed.unretryable_messages.count
  end

  test "a retry's result lists only the people it sent to again" do
    mixed = stopped_and_retryable

    post communication_rbs_retry_history_broadcast_path(mixed)

    assert_response :unprocessable_entity
    assert_select "th[scope=row]", text: "Mailed"
    assert_select "th[scope=row]", text: "Stopped", count: 0
    assert_no_match(/opted out/, response.body)
  end

  # Another run can send the failures between the guard and the retry reading
  # them. The page then says nothing went, and gives no reason it can't know.
  test "a retry that finds its failures already sent says only that nothing was sent again" do
    original = Rbs.method(:retry_broadcast)
    Rbs.define_singleton_method(:retry_broadcast) do |broadcast, retry_person_id|
      BroadcastMessage.where(broadcast_id: broadcast.id).update_all(status: Broadcast::STATUS_SENT)
      original.call(broadcast, retry_person_id)
    end

    post communication_rbs_retry_history_broadcast_path(@failed)

    assert_response :unprocessable_entity
    assert_select ".box-warning", text: /\A\s*Nothing was sent again\.\s*\z/
  ensure
    Rbs.define_singleton_method(:retry_broadcast, original)
  end
end
