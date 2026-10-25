# frozen_string_literal: true

require "test_helper"

class Communication::MailTemplatesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear

    @admin = person(:auditor_ranger)
    @vc = person(:retired_ranger)
    @outsider = person(:active_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "VC")
    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)

    @template = MailTemplate.find_by!(tag: "password_reset_mailer/notify")
    @piece = MailTemplate.find_by!(tag: "shared/mailer/do_not_reply")
  end

  teardown do
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- index

  test "the list shows a row per message" do
    sign_in_as(@admin)

    get communication_mail_templates_path

    assert_response :success
    assert_select "h1", text: /Email Templates/
    assert_select "tbody td .font-mono", text: %r{password_reset_mailer/notify}
  end

  # The badge, not the tag: "shared/mailer/..." holds the word in its own name.
  test "a piece shared by other messages is marked as one" do
    sign_in_as(@admin)

    get communication_mail_templates_path

    assert_response :success
    assert_select "tbody td .font-mono", text: %r{shared/mailer/do_not_reply} do
      assert_select ".badge", text: "shared", count: 1
    end
    assert_select "tbody td .font-mono", text: %r{password_reset_mailer/notify} do
      assert_select ".badge", count: 0
    end
  end

  test "a Volunteer Coordinator may read the list" do
    sign_in_as(@vc)

    get communication_mail_templates_path

    assert_response :success
  end

  test "anyone else is turned away" do
    sign_in_as(@outsider)

    get communication_mail_templates_path

    assert_redirected_to me_root_path
  end

  # ---------------------------------------------------------------- edit

  test "the edit page names the values the message fills in" do
    sign_in_as(@admin)

    get edit_communication_mail_template_path(@template)

    assert_response :success
    assert_select "code", text: "reset_url"
    assert_select "code", text: "support_email"
  end

  test "a shared piece is edited without a subject field" do
    sign_in_as(@admin)

    get edit_communication_mail_template_path(@piece)

    assert_response :success
    assert_select "input[name='mail_template[subject]']", count: 0
  end


  test "the form posts back to this template" do
    sign_in_as(@admin)

    get edit_communication_mail_template_path(@template)

    assert_response :success
    assert_select "form[action=?][method=post]", communication_mail_template_path(@template) do
      assert_select "input[name=_method][value=patch]", count: 1
      assert_select "input[type=submit], button[type=submit]", count: 1
    end
  end

  # ---------------------------------------------------------------- update

  test "saving new wording changes what the next message says" do
    sign_in_as(@admin)

    patch communication_mail_template_path(@template),
          params: { mail_template: { subject: "Reset your Clubhouse password",
                                     body: "<p>{{ greeting }}, use {{ reset_url }}</p>",
                                     text_body: @template.text_body } }

    assert_redirected_to communication_mail_templates_path

    mail = PasswordResetMailer.notify(person: person(:active_ranger), reset_token: "abc")

    assert_equal "Reset your Clubhouse password", mail.subject
    assert_includes mail.html_part.body.to_s, "use "
  end

  test "the person who saved it is recorded" do
    sign_in_as(@admin)

    patch communication_mail_template_path(@template),
          params: { mail_template: { subject: "A different subject", body: @template.body,
                                     text_body: @template.text_body } }

    assert_equal @admin.id, @template.reload.person_update_id
  end

  test "wording that cannot be understood is refused" do
    original = @template.body
    sign_in_as(@admin)

    patch communication_mail_template_path(@template),
          params: { mail_template: { subject: @template.subject, body: "{% if %}",
                                     text_body: @template.text_body } }

    assert_response :unprocessable_entity
    assert_equal original, @template.reload.body
  end

  test "the tag cannot be changed from this page" do
    sign_in_as(@admin)

    patch communication_mail_template_path(@template),
          params: { mail_template: { tag: "something_else/notify", subject: @template.subject,
                                     body: @template.body, text_body: @template.text_body } }

    assert_equal "password_reset_mailer/notify", @template.reload.tag
  end

  test "anyone else cannot save" do
    original = @template.subject
    sign_in_as(@outsider)

    patch communication_mail_template_path(@template),
          params: { mail_template: { subject: "Hijacked", body: @template.body } }

    assert_redirected_to me_root_path
    assert_equal original, @template.reload.subject
  end
end
