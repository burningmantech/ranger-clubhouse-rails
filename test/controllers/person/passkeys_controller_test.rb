# frozen_string_literal: true

require "test_helper"

class Person::PasskeysControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include PasskeyTestHelper

  setup do
    Current.reset

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @non_admin = person(:echelon_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)
    # Admitted to the person pages, and still not to this one.
    grant_role(@non_admin, Role::VC)

    @admin.password = "admin-password"
    @admin.save!(validate: false)
    @target.password = "target-password"
    @target.save!(validate: false)

    @own = add_passkey_row(@target, nickname: "Own Phone", last_used_at: Time.zone.local(2026, 9, 1, 8, 30))
    @enrolled = add_passkey_row(@target, nickname: "HQ Security Key", added_by: @admin)
  end

  teardown do
    Current.reset
  end

  # --- index ---

  test "index lists the account's passkeys for an Admin, and who added each" do
    add_passkey_row(@non_admin, nickname: "Someone Else's Laptop")
    sign_in_as(@admin)

    get person_passkeys_path(@target)

    assert_response :success
    assert_select "h1", text: /Passkeys\s+—\s+#{@target.callsign}/
    assert_select "th[scope=row]", text: "Own Phone"
    assert_select "th[scope=row]", text: "HQ Security Key"
    assert_select "body", text: /Someone Else's Laptop/, count: 0

    own_row = css_select("tr").find { |row| row.text.include?("Own Phone") }
    assert_match(/Self/, own_row.text)
    assert_no_match(/Never/, own_row.text)

    enrolled_row = css_select("tr").find { |row| row.text.include?("HQ Security Key") }
    assert_match(/#{@admin.callsign}\s+Admin/, enrolled_row.text)
    assert_match(/Never/, enrolled_row.text)

    assert_select "a[href='#{person_passkey_path(@target, @own)}']", text: /Delete/
    assert_select "a[href='#{person_sessions_path(@target)}']", text: "Login Sessions"
  end

  # The Admin who enrolled a key can be deleted later. The key must go on
  # reading as someone else's doing, never as the person's own.
  test "index does not pass off an enrolled key as self-added once that Admin is gone" do
    @enrolled.update_columns(added_by_person_id: Person.maximum(:id) + 1)
    sign_in_as(@admin)

    get person_passkeys_path(@target)

    enrolled_row = css_select("tr").find { |row| row.text.include?("HQ Security Key") }
    assert_match(/A deleted account\s+Admin/, enrolled_row.text)
    assert_no_match(/Self/, enrolled_row.text)
  end

  test "index for an account with no passkeys says so" do
    @target.passkeys.destroy_all
    sign_in_as(@admin)

    get person_passkeys_path(@target)

    assert_response :success
    assert_select "body", text: /#{@target.callsign} has no passkeys\./
  end

  test "index is denied to a person-page role without Admin" do
    sign_in_as(@non_admin)

    get person_passkeys_path(@target)

    assert_redirected_to me_root_path
  end

  test "index for a person who does not exist goes back to the dashboard" do
    sign_in_as(@admin)

    get person_passkeys_path(Person.maximum(:id) + 1)

    assert_redirected_to me_root_path
  end

  test "the person pages' menu leads here for an Admin" do
    sign_in_as(@admin)

    get person_passkeys_path(@target)

    assert_select "a[href='#{person_passkeys_path(@target)}']", text: /Passkeys/
  end

  # --- destroy ---

  test "an Admin removes a passkey, and the log says who did it and to whom" do
    ActionLog.delete_all
    sign_in_as(@admin)

    assert_difference -> { @target.passkeys.count }, -1 do
      delete person_passkey_path(@target, @own)
    end

    assert_redirected_to person_passkeys_path(@target)
    assert_equal "Own Phone can no longer sign in as #{@target.callsign}.", flash[:success]

    entry = ActionLog.where(event: "person-passkey-delete").last
    assert_equal @admin.id, entry.person_id
    assert_equal @target.id, entry.target_person_id
    assert_equal "Own Phone", entry.data["nickname"]
  end

  # The person hears of it, and from whom. It is what keeps an Admin's hand on
  # someone's account from being a quiet one.
  test "an Admin removing a passkey emails the person, naming the Admin" do
    sign_in_as(@admin)

    assert_enqueued_email_with PasskeyMailer, :removed, params: { sender_id: @admin.id },
                                                         args: [{ person: @target, nickname: "Own Phone", by: @admin }] do
      delete person_passkey_path(@target, @own)
    end
  end

  test "destroy is denied to a person-page role without Admin" do
    sign_in_as(@non_admin)

    assert_no_enqueued_emails do
      assert_no_difference -> { PersonPasskey.count } do
        delete person_passkey_path(@target, @own)
      end
    end

    assert_redirected_to me_root_path
  end

  test "destroy cannot reach a passkey on some other account" do
    theirs = add_passkey_row(@non_admin, nickname: "Not This Account's")
    sign_in_as(@admin)

    assert_no_difference -> { PersonPasskey.count } do
      delete person_passkey_path(@target, theirs)
    end

    assert_response :not_found
  end

  # --- enrolling a security key for someone ---

  test "index offers Add Security Key, and new is the form the script drives" do
    sign_in_as(@admin)

    get person_passkeys_path(@target)
    assert_select "a[href='#{new_person_passkey_path(@target)}']", text: /Add Security Key/

    get new_person_passkey_path(@target)
    assert_response :success
    assert_select "h1", text: /Add Security Key\s+—\s+#{@target.callsign}/
    assert_select "h2", text: "Before You Start"
    assert_select "form[action='#{person_passkeys_path(@target)}'][data-controller~=passkey][data-turbo=false]" \
                  "[data-passkey-ceremony-value=create][data-passkey-options-url-value='#{options_person_passkeys_path(@target)}']" do
      assert_select "input[name='passkey_form[nickname]'][value='Security Key']"
      assert_select "label", text: /Your Current Password/
      assert_select "input[type=password][name='passkey_form[current_password]']"
      assert_select "input[type=hidden][name='passkey_form[credential]']"
      assert_select "input[type=submit][value='Add Security Key']"
    end
  end

  test "the options steer the browser to a security key, and are made out to the person, not the Admin" do
    sign_in_as(@admin)

    options = request_enrollment_options

    assert_response :success
    assert_equal "cross-platform", options.dig("authenticatorSelection", "authenticatorAttachment")
    assert_equal "required", options.dig("authenticatorSelection", "residentKey")
    assert_equal "required", options.dig("authenticatorSelection", "userVerification")
    assert_equal ["security-key"], options["hints"]
    assert_equal @target.email, options.dig("user", "name")
    assert_equal PersonPasskey.user_handle(@target), options.dig("user", "id")
    assert_equal [@own.external_id, @enrolled.external_id].sort, options["excludeCredentials"].pluck("id").sort
    assert_equal @target.id, session[Passkeys::Registration::SESSION_KEY]["person_id"]
  end

  # The Admin proves it is them. The person's own password is no use here --
  # it is not theirs to type.
  test "it is the Admin's password that is asked for, and a wrong one starts nothing" do
    sign_in_as(@admin)

    request_enrollment_options(current_password: "target-password")
    assert_response :unprocessable_entity
    assert_equal "That is not your current password.", response.parsed_body["error"]
    assert_nil session[Passkeys::Registration::SESSION_KEY]

    request_enrollment_options(current_password: "admin-password")
    assert_response :success
  end

  test "an Admin enrolls a security key: it is on the person's account, in the Admin's name, logged and emailed" do
    ActionLog.delete_all
    sign_in_as(@admin)
    options = request_enrollment_options(nickname: "HQ Key 7")

    assert_enqueued_email_with PasskeyMailer, :added, params: { sender_id: @admin.id },
                                                       args: [{ person: @target, nickname: "HQ Key 7", by: @admin }] do
      assert_difference -> { @target.passkeys.count }, 1 do
        post person_passkeys_path(@target),
             params: { passkey_form: { credential: passkey_credential_for(options, attachment: "cross-platform") } }
      end
    end

    assert_redirected_to person_passkeys_path(@target)
    assert_equal "HQ Key 7 can now sign in as #{@target.callsign}, and an email went to #{@target.callsign}.", flash[:success]

    passkey = @target.passkeys.find_by!(nickname: "HQ Key 7")
    assert_equal @admin, passkey.added_by
    assert_predicate passkey, :added_by_admin?
    assert_equal 0, @admin.passkeys.count, "nothing may land on the Admin's own account"

    entry = ActionLog.where(event: "person-passkey-create").last
    assert_equal @admin.id, entry.person_id
    assert_equal @target.id, entry.target_person_id
  end

  # The hazard this page exists to contain: the device's part happens in the
  # Admin's browser, so the passkey could land in the Admin's own password
  # manager, and those passkeys copy themselves between devices.
  test "a passkey that can be copied between devices is refused, recorded, and emails no one" do
    ErrorLog.delete_all
    sign_in_as(@admin)
    options = request_enrollment_options

    assert_no_enqueued_emails do
      assert_no_difference -> { PersonPasskey.count } do
        post person_passkeys_path(@target),
             params: { passkey_form: { credential: passkey_credential_for(options, attachment: "cross-platform",
                                                                                   backup_eligibility: true, backup_state: true) } }
      end
    end

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /cannot be enrolled for someone else\. Use a hardware security key/
    entry = ErrorLog.where(error_type: "passkey-enrollment-not-hardware").last
    assert_equal @target.id, entry.data["person_id"]
    assert_equal @admin.id, entry.data["actor_id"]
  end

  test "a passkey the browser says came from the computer itself is refused" do
    sign_in_as(@admin)
    options = request_enrollment_options

    assert_no_difference -> { PersonPasskey.count } do
      post person_passkeys_path(@target),
           params: { passkey_form: { credential: passkey_credential_for(options, attachment: "platform") } }
    end

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /Use a hardware security key/
  end

  # A registration belongs to the account it was begun for. An Admin with two
  # tabs open cannot start on their own account and finish on someone else's,
  # nor the other way about -- where the hardware rule would not apply.
  test "a registration begun on the Admin's own account cannot be finished on the person's, nor the reverse" do
    sign_in_as(@admin)

    post options_me_profile_passkeys_path, params: { passkey_form: { nickname: "Mine", current_password: "admin-password" } }
    own_options = response.parsed_body
    assert_no_difference -> { PersonPasskey.count } do
      post person_passkeys_path(@target),
           params: { passkey_form: { credential: passkey_credential_for(own_options, attachment: "cross-platform") } }
    end
    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /That took too long/

    their_options = request_enrollment_options
    assert_no_difference -> { PersonPasskey.count } do
      post me_profile_passkeys_path, params: { passkey_form: { credential: passkey_credential_for(their_options) } }
    end
    assert_response :unprocessable_entity
  end

  test "enrolling is denied to a person-page role without Admin" do
    sign_in_as(@non_admin)

    get new_person_passkey_path(@target)
    assert_redirected_to me_root_path

    post options_person_passkeys_path(@target), params: { passkey_form: { nickname: "x", current_password: "x" } }
    assert_redirected_to me_root_path

    assert_no_difference -> { PersonPasskey.count } do
      post person_passkeys_path(@target), params: { passkey_form: { credential: "{}" } }
    end
    assert_redirected_to me_root_path
  end

  test "a key cannot be enrolled where this Clubhouse offers no passkeys, and the page does not offer to" do
    switch_passkeys_off
    sign_in_as(@admin)

    get person_passkeys_path(@target)
    assert_select "a", text: /Add Security Key/, count: 0

    get new_person_passkey_path(@target)
    assert_redirected_to person_passkeys_path(@target)
    assert_equal "Passkeys are switched off on this Clubhouse.", flash[:error]

    request_enrollment_options
    assert_redirected_to person_passkeys_path(@target)

    assert_no_difference -> { PersonPasskey.count } do
      post person_passkeys_path(@target), params: { passkey_form: { credential: "{}" } }
    end
    assert_redirected_to person_passkeys_path(@target)
  end

  # --- where passkeys are off ---

  # Switching passkeys off leaves the rows on file, and an Admin must still be
  # able to see and clear them.
  test "an Admin can still see and remove passkeys where this Clubhouse offers none" do
    switch_passkeys_off
    sign_in_as(@admin)

    get person_passkeys_path(@target)
    assert_response :success
    assert_select "th[scope=row]", text: "Own Phone"

    assert_difference -> { @target.passkeys.count }, -1 do
      delete person_passkey_path(@target, @own)
    end
  end

  private

  def request_enrollment_options(nickname: "Security Key", current_password: "admin-password")
    post options_person_passkeys_path(@target),
         params: { passkey_form: { nickname: nickname, current_password: current_password } }
    response.parsed_body
  end
end
