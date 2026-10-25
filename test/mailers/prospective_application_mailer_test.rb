# frozen_string_literal: true

require "test_helper"

class ProspectiveApplicationMailerTest < ActionMailer::TestCase
  test "every prospective application view renders" do
    app = prospective_application(:pending_qualified)
    app.update_columns(regional_callsign: "Regional Rex", regional_experience: "Ranged elsewhere",
                       approved_handle: "Dusty Dawn")

    %w[age_confirmation approved_callsign experience_confirmation more_handles pii_issue
       reject_regional reject_too_young reject_unqualified returning_ranger why_ranger_question].each do |name|
      klass = "ProspectiveApplication::#{name.camelize}Mailer".constantize
      body = klass.notify(application: app, status: "pending", message_to_user: "A note").body.to_s
      assert_no_match(/mj-/, body, "#{name} still emits MJML")
      assert_no_match(/<%/, body, "#{name} leaked raw ERB")
      assert_match(/Alice Applicant|Alice,/, body, "#{name} did not interpolate")
      assert_match(/<html/i, body, "#{name} missing layout")
    end

    assert_match(/Regional Rex/,
                 ProspectiveApplication::RrnCheckMailer.check(application: app, status: "pending").body.to_s)
    assert_match(/Hello/,
                 ProspectiveApplication::ApprovedReminderMailer.notify(applications: [app]).body.to_s)
    assert_match(/Hi there/,
                 ProspectiveApplication::SendEmailMailer.send_message(application: app, email_subject: "s",
                                                                     email_message: "Hi there").body.to_s)
    assert_match(/Reset Your Password/,
                 PasswordResetMailer.notify(person: person(:active_ranger), reset_token: "t").html_part.body.to_s)
  end

  # The VC application's Mail Log section lists an application's mail by this.
  test "every email about an application is logged under it" do
    app = prospective_application(:pending_qualified)
    Setting.find_or_initialize_by(name: Setting::RRN_EMAIL).update!(value: "rrn@example.com")

    [
      ProspectiveApplication::MoreHandlesMailer.notify(application: app, status: "pending"),
      ProspectiveApplication::RrnCheckMailer.check(application: app, status: "pending"),
      ProspectiveApplication::SendEmailMailer.send_message(application: app, email_subject: "s", email_message: "Hi")
    ].each do |delivery|
      mail = delivery.deliver_now

      assert_equal [app.id], MailLog.where(message_id: mail.message_id).pluck(:prospective_application_id),
                   "#{delivery.message.delivery_handler.name} lost its application"
    end
  end

  # A returning applicant, or mail after the account was made: the address
  # belongs to an account, so the email shows on that person's Mail Log too.
  test "applicant mail to an address an account holds is logged under that person" do
    app = prospective_application(:pending_qualified)
    ranger = person(:active_ranger)
    app.update_columns(email: ranger.email)

    mail = ProspectiveApplication::MoreHandlesMailer.notify(application: app, status: "pending").deliver_now

    assert_equal [[ranger.id, app.id]], MailLog.where(message_id: mail.message_id)
                                               .pluck(:person_id, :prospective_application_id)
  end

  # The sandbox sends applicant mail to the address it names instead, so that
  # address's holder is who the row belongs to.
  test "sandboxed applicant mail is logged under whoever holds the sandbox address" do
    app = prospective_application(:pending_qualified)
    vc = person(:echelon_ranger)
    Setting.find_or_initialize_by(name: Setting::PROSPECTIVE_APPLICATION_MAIL_SANDBOX).update!(value: vc.email)

    mail = ProspectiveApplication::MoreHandlesMailer.notify(application: app, status: "pending").deliver_now

    assert_equal [[vc.email, vc.id, app.id]], MailLog.where(message_id: mail.message_id)
                                                     .pluck(:to_email, :person_id, :prospective_application_id)
  end
end
