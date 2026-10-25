# frozen_string_literal: true

require "test_helper"

class ApplicationMailerTest < ActionMailer::TestCase
  include SesTestHelper

  setup do
    @person = person(:active_ranger)
    @vc = person(:echelon_ranger)
  end

  # The training server runs on a copy of real accounts. Anything it sends goes
  # to the people in that copy, so nothing is allowed to leave it.
  test "mail is held back on the training server" do
    Current.groundhog_day_time = Time.zone.local(Current.year, 6, 1, 12, 0, 0)

    mail = ExpiredHandleReservationsMailer.notify(handles: [])

    assert_not mail.perform_deliveries
  ensure
    Current.groundhog_day_time = nil
  end

  test "mail is sent normally everywhere else" do
    mail = ExpiredHandleReservationsMailer.notify(handles: [])

    assert mail.perform_deliveries
  end

  # Settings keep an email list one address per line. Left whole, the list went
  # out as a single address with a line break in it, which SMTP delivery refuses.
  test "a setting listing several addresses sends to each of them" do
    Setting.find_or_create_by(name: Setting::TAS_SAP_REPORT_EMAIL).update!(value: "a@example.com,b@example.com")

    mail = RangersWhoNeedSapsMailer.notify(rows: [], start_year: 2023)

    assert_equal ["a@example.com", "b@example.com"], mail.to
  end

  # A training server whose time is written wrongly is still a training server.
  # Reading that time is what used to decide, so a typo turned the hold-back
  # off and the copy started mailing the real people in it.
  test "mail is held back even when the training server's time cannot be read" do
    previous = ENV.fetch("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME", nil)
    ENV["RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"] = "the middle of the burn"
    Current.groundhog_day_time = nil

    assert_not ExpiredHandleReservationsMailer.notify(handles: []).perform_deliveries
  ensure
    previous.nil? ? ENV.delete("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME") : ENV["RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"] = previous
  end

  # --- the mail log ---

  test "an email sent now leaves a row for each To address, with its text" do
    Setting.find_or_create_by(name: Setting::TAS_SAP_REPORT_EMAIL).update!(value: "#{@person.email},b@example.com")
    Current.person = @vc

    mail = RangersWhoNeedSapsMailer.notify(rows: [], start_year: 2023).deliver_now

    rows = MailLog.where(message_id: mail.message_id).order(:id).to_a
    assert_equal [@person.email, "b@example.com"], rows.map(&:to_email)
    assert_equal [@person.id, nil], rows.map(&:person_id)
    rows.each do |row|
      assert_equal @vc.id, row.sender_id
      assert_equal mail.subject, row.subject
      assert row.was_sent
      assert_not row.body_withheld?
      assert_includes row.body, "No Rangers found who may need SAPs."
    end
  end

  # A queued email is built again in a job, where nobody is signed in, so the
  # sender has to travel with it. Current.reset would keep the person, so the
  # test clears it by hand.
  test "a queued email is logged under the sender it was queued with" do
    Current.person = @vc
    PasskeyMailer.with(sender_id: @vc.id).added(person: @person, nickname: "My Phone", by: @vc).deliver_later
    Current.person = nil

    assert_difference "MailLog.count", 1 do
      perform_enqueued_jobs
    end

    row = logged_row(ActionMailer::Base.deliveries.last)
    assert_equal @vc.id, row.sender_id
    assert_equal @person.id, row.person_id
    assert_not row.body_withheld?
  end

  test "a queued email with no sender is logged with none" do
    Current.person = @vc
    PasskeyMailer.added(person: @person, nickname: "My Phone", by: @person).deliver_later
    Current.person = nil

    perform_enqueued_jobs

    assert_nil logged_row(ActionMailer::Base.deliveries.last).sender_id
  end

  test "a queued email sent through SES is logged under the id SES gave it" do
    with_ses_mail do |calls|
      PasskeyMailer.with(sender_id: @vc.id).added(person: @person, nickname: "My Phone", by: @vc).deliver_later
      perform_enqueued_jobs

      assert_equal 1, calls.size
    end

    row = MailLog.find_by!(message_id: SES_MAIL_ID)
    assert_equal [@person.email, @vc.id], [row.to_email, row.sender_id]
  end

  # An action that never calls mail() leaves a stand-in message with no
  # address at all, whose body cannot be read.
  test "a message with no To address leaves no row and no error" do
    mailer = ExpiredHandleReservationsMailer.new
    mailer.define_singleton_method(:notify) { |**| nil }
    mailer.process(:notify, handles: [])

    assert_no_difference ["MailLog.count", "ErrorLog.count"] do
      mailer.run_callbacks(:deliver) { mailer.message.deliver }
    end
  end

  test "a held email with every recipient taken off leaves no row and no error" do
    drop_everyone = Class.new do
      def self.delivering_email(message)
        message.to = nil
        message.perform_deliveries = false
      end
    end
    ActionMailer::Base.register_interceptor(drop_everyone)

    assert_no_difference ["MailLog.count", "ErrorLog.count"] do
      PasskeyMailer.added(person: @person, nickname: "My Phone", by: @person).deliver_now
    end
  ensure
    ActionMailer::Base.unregister_interceptor(drop_everyone)
  end

  test "held mail on the training server is logged as not sent" do
    Current.groundhog_day_time = Time.zone.local(Current.year, 6, 1, 12, 0, 0)

    mail = PasskeyMailer.added(person: @person, nickname: "My Phone", by: @person).deliver_now

    assert_empty ActionMailer::Base.deliveries
    assert_not logged_row(mail).was_sent
  ensure
    Current.groundhog_day_time = nil
  end

  # The email has gone by the time its rows are written. A password reset's
  # page or a mail job must not fail over the log.
  test "a mail log that cannot be written never fails an email sent now" do
    with_failing_mail_log do
      assert_difference ["ActionMailer::Base.deliveries.size", "ErrorLog.count"], 1 do
        PasskeyMailer.added(person: @person, nickname: "My Phone", by: @person).deliver_now
      end
    end

    assert_logged_failure("PasskeyMailer", "added")
  end

  test "a mail log that cannot be written never fails a mail job" do
    PasskeyMailer.removed(person: @person, nickname: "My Phone", by: @person).deliver_later

    with_failing_mail_log do
      assert_difference ["ActionMailer::Base.deliveries.size", "ErrorLog.count"], 1 do
        perform_enqueued_jobs
      end
    end

    assert_logged_failure("PasskeyMailer", "removed")
  end

  # --- mail whose text the log never keeps ---

  test "a password reset is logged without its text" do
    mail = PasswordResetMailer.notify(person: @person, reset_token: "reset-secret").deliver_now

    row = assert_logged_without_body(mail, sender: nil)
    assert_equal "Ranger Clubhouse Password Reset", row.subject
  end

  test "a welcome email is logged without its text" do
    WelcomeMailer.with(sender_id: @vc.id).notify(person: @person, invite_token: "invite-secret").deliver_later
    Current.person = nil
    perform_enqueued_jobs

    assert_logged_without_body(ActionMailer::Base.deliveries.last, sender: @vc)
  end

  test "an online course password email is logged without its text" do
    Current.person = @vc

    mail = OnlineCourseResetPasswordMailer.notify(person: @person, password: "moodle-secret").deliver_now

    assert_logged_without_body(mail, sender: @vc)
  end

  test "a group message's alert says so, from the name the message was written under" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")

    Rbs.message_notify(@person, @vc.id, "Green Dot Cadre", "Shift swap", "Something private", group: true)
    perform_enqueued_jobs

    mail = ActionMailer::Base.deliveries.last
    assert_equal "[Clubhouse Group Message] Shift swap", mail.subject
    assert_match(/group message\. Everyone in the conversation sees every reply\./, mail.body.encoded)
    assert_match(/From: Green Dot Cadre/, mail.body.encoded)
  end

  # Review finding: a group keyword on notify raised on the release before it
  # while a rolling deploy overlapped them; group is a param instead.
  test "the new-message mailer takes the keywords the release before it took, and group as a param" do
    assert_equal %i[person from subject message to], ClubhouseNewMessageMailer.instance_method(:notify).parameters.map(&:last)
  end

  # Review finding: the mail log named the author of a message written as a
  # team to VCs who may not be on the team.
  test "a group alert for a message written as a team is logged with no sender" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")

    Rbs.message_notify(@person, @vc.id, "Green Dot Cadre", "Shift swap", "Something private", group: true, anonymous: true)
    perform_enqueued_jobs

    row = MailLog.order(:id).last
    assert_equal "[Clubhouse Group Message] Shift swap", row.subject
    assert_nil row.sender_id
    assert_equal @vc.id, Broadcast.order(:id).last.sender_id, "the broadcast row keeps the author for Admin and Tech Ninja"
  end

  test "a new-message alert is logged under its sender, without its text" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")

    Rbs.message_notify(@person, @vc.id, @vc.callsign, "Shift swap", "Something private")
    perform_enqueued_jobs

    row = assert_logged_without_body(ActionMailer::Base.deliveries.last, sender: @vc)
    assert_equal "[Clubhouse Message] Shift swap", row.subject
  end

  test "a message one person sends another is logged without its text" do
    Current.person = @vc

    mail = ContactMailer.send_message(sender_person: @vc, person: @person, message_subject: "Saying hello",
                                      contact_message: "Something private").deliver_now

    assert_logged_without_body(mail, sender: @vc)
  end

  # --- links ---

  # Every message can name this Clubhouse, on the host the mailer is set to.
  # liquid_assigns is private, so it is read through an email that prints it as
  # both the link and its text.
  test "a message links to this Clubhouse as clubhouse_url" do
    mail = ProspectiveApplication::ReturningRangerMailer.notify(
      application: prospective_application(:pending_qualified),
      status: ProspectiveApplication::STATUS_REJECT_RETURNING_RANGER
    )

    assert_includes mail.body.to_s, %(<a href="http://example.com/">http://example.com/</a>)
  end

  private

  # The one row an email left: it went to one address.
  def logged_row(mail)
    rows = MailLog.where(message_id: mail.message_id).to_a
    assert_equal 1, rows.size, "expected one mail log row for #{mail.subject.inspect}"
    rows.first
  end

  # Everything about the email but its text: the body column keeps its NULL.
  def assert_logged_without_body(mail, sender:)
    row = logged_row(mail)
    assert_equal [mail.subject, sender&.id, @person.id, @person.email],
                 [row.subject, row.sender_id, row.person_id, row.to_email]
    assert row.body_withheld?
    assert_nil MailLog.where(id: row.id).pick(:body)
    row
  end

  def with_failing_mail_log
    original = MailLog.method(:record_delivery)
    MailLog.define_singleton_method(:record_delivery) { |*, **| raise ActiveRecord::StatementInvalid, "no room" }
    yield
  ensure
    MailLog.define_singleton_method(:record_delivery, original)
  end

  def assert_logged_failure(mailer, action)
    log = ErrorLog.order(:id).last
    assert_equal "mail-log-exception", log.error_type
    assert_equal({ "mailer" => mailer, "action" => action }, log.data.slice("mailer", "action"))
  end
end
