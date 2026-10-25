# frozen_string_literal: true

require "test_helper"

class Me::PasskeysControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include PasskeyTestHelper

  setup do
    @person = person(:active_ranger)
    @person.password = "password"
    @person.save!(validate: false)
    @other = person(:auditor_ranger)
    sign_in_as(@person)
  end

  # --- index ---

  test "index lists my passkeys and no one else's" do
    mine = add_passkey_row(@person, nickname: "My Phone")
    add_passkey_row(@other, nickname: "Someone Else's Laptop")

    get me_profile_passkeys_path

    assert_response :success
    assert_select "th[scope=row]", text: /My Phone/
    assert_select "body", text: /Someone Else's Laptop/, count: 0
    assert_select "a[href='#{me_profile_passkey_path(mine)}']", text: /Delete/
    assert_select "a[href='#{new_me_profile_passkey_path}']", text: /Add Passkey/
  end

  test "index says who added a passkey an Admin enrolled, even when that Admin is gone" do
    add_passkey_row(@person, nickname: "Own Key")
    add_passkey_row(@person, nickname: "Handed Over", added_by: @other)
    add_passkey_row(@person, nickname: "Orphaned", added_by_person_id: Person.maximum(:id) + 1)

    get me_profile_passkeys_path

    assert_select "th[scope=row]", text: /Handed Over\s+Added by #{@other.callsign}/
    assert_select "th[scope=row]", text: /Orphaned\s+Added by an Admin/
    assert_select "th[scope=row]", text: /Own Key/ do |cells|
      assert_no_match(/Added by/, cells.first.text)
    end
  end

  test "index with no passkeys says so and still explains them" do
    get me_profile_passkeys_path

    assert_response :success
    assert_select "body", text: /No passkeys yet\./
    assert_select "a[href='#about-passkeys']"
    assert_select "#about-passkeys dt", minimum: 4
  end

  test "index sends a signed-out visitor to the door" do
    sign_out

    get me_profile_passkeys_path

    assert_redirected_to root_path
  end

  # --- new ---

  test "new offers the form the script drives, with a nickname already suggested" do
    get new_me_profile_passkey_path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36" }

    assert_response :success
    assert_select "form[action='#{me_profile_passkeys_path}'][data-controller~=passkey][data-turbo=false]" \
                  "[data-passkey-ceremony-value=create][data-passkey-options-url-value='#{options_me_profile_passkeys_path}']" do
      assert_select "input[name='passkey_form[nickname]'][value='Chrome on Mac OS X']"
      assert_select "input[type=password][name='passkey_form[current_password]'][data-passkey-target=password]"
      assert_select "input[type=hidden][name='passkey_form[credential]'][data-passkey-target=credential]"
      assert_select "input[type=submit][value='Add Passkey'][data-passkey-target=submit]"
      assert_select "[data-passkey-target=error][hidden]"
      assert_select "[data-passkey-target=unsupported][hidden]"
    end
  end

  # --- options: everything refusable is refused before the device makes anything ---

  test "options with the right password answers with what the browser hands the device" do
    existing = add_passkey_row(@person, nickname: "Already Here")

    options = request_options(nickname: "  My   Phone ")

    assert_response :success
    assert_equal "www.example.com", options.dig("rp", "id")
    assert_equal "Ranger Clubhouse", options.dig("rp", "name")
    assert_equal @person.email, options.dig("user", "name")
    assert_equal @person.callsign, options.dig("user", "displayName")
    assert_equal PersonPasskey.user_handle(@person), options.dig("user", "id")
    assert_equal({ "residentKey" => "required", "userVerification" => "required" }, options["authenticatorSelection"])
    assert_equal [existing.external_id], options["excludeCredentials"].pluck("id")
    assert_predicate options["challenge"], :present?

    pending = session[Passkeys::Registration::SESSION_KEY]
    assert_equal options["challenge"], pending["challenge"]
    assert_equal "My Phone", pending["nickname"]
    assert_equal @person.id, pending["person_id"]
  end

  test "options with the wrong password is refused and starts nothing" do
    request_options(current_password: "not it")

    assert_response :unprocessable_entity
    assert_equal "That is not your current password.", response.parsed_body["error"]
    assert_nil session[Passkeys::Registration::SESSION_KEY]
  end

  test "options without a nickname is refused and starts nothing" do
    request_options(nickname: "   ")

    assert_response :unprocessable_entity
    assert_equal "Give the passkey a nickname.", response.parsed_body["error"]
    assert_nil session[Passkeys::Registration::SESSION_KEY]
  end

  test "options for an account that is full is refused and starts nothing" do
    fill_passkeys(@person)

    request_options

    assert_response :unprocessable_entity
    assert_equal PersonPasskey::LIMIT_MESSAGE, response.parsed_body["error"]
    assert_nil session[Passkeys::Registration::SESSION_KEY]
  end

  test "options sent by hand in the wrong shape is refused, not an error page" do
    post options_me_profile_passkeys_path, params: { passkey_form: "x" }
    assert_response :unprocessable_entity

    post options_me_profile_passkeys_path, params: { passkey_form: { nickname: ["x"], current_password: { a: "b" } } }
    assert_response :unprocessable_entity
  end

  # --- create ---

  test "adding a passkey saves it under the tidied nickname and says so" do
    ActionLog.delete_all
    options = request_options(nickname: "  My   Phone ")

    assert_difference -> { @person.passkeys.count }, 1 do
      post me_profile_passkeys_path, params: { passkey_form: { credential: passkey_credential_for(options) } }
    end

    assert_redirected_to me_profile_passkeys_path
    assert_equal "My Phone can now sign you in.", flash[:success]

    passkey = @person.passkeys.last
    assert_equal "My Phone", passkey.nickname
    assert_not passkey.added_by_admin?
    assert_predicate passkey.external_id, :present?
    assert_predicate passkey.public_key, :present?
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, passkey.aaguid)

    entry = ActionLog.where(event: "person-passkey-create").last
    assert_equal @person.id, entry.target_person_id
    assert_not entry.data.key?("public_key")
  end

  # The hardware-only rule is for an Admin enrolling a key on someone else's
  # account. A person's own phone and password manager are exactly what their
  # own page is for.
  test "my own passkey may be one that copies between my devices" do
    options = request_options
    assert_nil options.dig("authenticatorSelection", "authenticatorAttachment")
    assert_nil options["hints"]

    assert_difference -> { @person.passkeys.count }, 1 do
      post me_profile_passkeys_path,
           params: { passkey_form: { credential: passkey_credential_for(options, backup_eligibility: true, backup_state: true) } }
    end
  end

  test "what the device made cannot be sent twice" do
    options = request_options
    credential = passkey_credential_for(options)
    post me_profile_passkeys_path, params: { passkey_form: { credential: credential } }
    assert_redirected_to me_profile_passkeys_path

    assert_no_difference -> { PersonPasskey.count } do
      post me_profile_passkeys_path, params: { passkey_form: { credential: credential } }
    end

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /That took too long\. Add the passkey again\./
  end

  test "a passkey sent without asking for options first is refused" do
    assert_no_difference -> { PersonPasskey.count } do
      post me_profile_passkeys_path, params: { passkey_form: { credential: "{}" } }
    end

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /That took too long/
  end

  test "a device that takes longer than five minutes has to start again" do
    options = request_options

    travel 6.minutes do
      assert_no_difference -> { PersonPasskey.count } do
        post me_profile_passkeys_path, params: { passkey_form: { credential: passkey_credential_for(options) } }
      end
    end

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /That took too long/
  end

  # The registration belongs to the account it was begun for. Someone else
  # signing in on the same browser cannot finish it onto their own account.
  test "a registration begun for one account cannot be finished on another" do
    options = request_options
    sign_in_as(@other)

    assert_no_difference -> { PersonPasskey.count } do
      post me_profile_passkeys_path, params: { passkey_form: { credential: passkey_credential_for(options) } }
    end

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /That took too long/
  end

  test "a passkey made on another website is refused, and the reason is recorded" do
    ErrorLog.delete_all
    options = request_options
    elsewhere = WebAuthn::FakeClient.new("https://clubhouse.example.net")
    credential = elsewhere.create(challenge: options["challenge"], rp_id: "www.example.com", user_verified: true).to_json

    assert_no_difference -> { PersonPasskey.count } do
      post me_profile_passkeys_path, params: { passkey_form: { nickname: "My Phone", credential: credential } }
    end

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /could not check that passkey/
    assert_select "input[name='passkey_form[nickname]'][value='My Phone']"

    entry = ErrorLog.where(error_type: "passkey-registration-refused").last
    assert_equal "WebAuthn::OriginVerificationError", entry.data["reason"]
    assert_equal @person.id, entry.data["person_id"]
  end

  test "a passkey made without a fingerprint, face or PIN is refused" do
    options = request_options

    assert_no_difference -> { PersonPasskey.count } do
      post me_profile_passkeys_path,
           params: { passkey_form: { credential: passkey_credential_for(options, user_verified: false) } }
    end

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /could not check that passkey/
  end

  # The library raises whatever its parsers raise when handed bytes it cannot
  # read. None of it may become an error page.
  test "a forged or mangled passkey is refused, not an error page" do
    good = JSON.parse(passkey_credential_for(request_options))
    forgeries = [
      "", "not json", "[]", "{}", "42",
      good.except("response").to_json,
      good.merge("response" => "x").to_json,
      good.merge("type" => "password").to_json,
      good.merge("id" => ["x"]).to_json,
      good.merge("response" => good["response"].merge("attestationObject" => "!!!")).to_json,
      good.merge("response" => good["response"].merge("attestationObject" => Base64.urlsafe_encode64(SecureRandom.bytes(60), padding: false))).to_json,
      good.merge("response" => good["response"].merge("clientDataJSON" => Base64.urlsafe_encode64("nope", padding: false))).to_json
    ]

    forgeries.each do |forgery|
      request_options
      assert_no_difference -> { PersonPasskey.count }, "#{forgery.first(40)} was kept" do
        post me_profile_passkeys_path, params: { passkey_form: { credential: forgery } }
      end
      assert_response :unprocessable_entity
      assert_select "#form-error-summary", text: /could not check that passkey/
    end

    request_options
    post me_profile_passkeys_path, params: { passkey_form: { credential: ["x"] } }
    assert_response :unprocessable_entity
  end

  test "a passkey that is already on another account is refused" do
    options = request_options
    credential = passkey_credential_for(options)
    add_passkey_row(@other, nickname: "Got There First", external_id: JSON.parse(credential)["id"])

    assert_no_difference -> { PersonPasskey.count } do
      post me_profile_passkeys_path, params: { passkey_form: { credential: credential } }
    end

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /already on a Clubhouse account/
  end

  # --- the notice ---

  test "adding a passkey emails the person, naming the passkey and that they did it" do
    options = request_options(nickname: "My Phone")

    assert_enqueued_email_with PasskeyMailer, :added, params: { sender_id: @person.id },
                                                       args: [{ person: @person, nickname: "My Phone", by: @person }] do
      post me_profile_passkeys_path, params: { passkey_form: { credential: passkey_credential_for(options) } }
    end
  end

  test "removing a passkey emails the person too" do
    passkey = add_passkey_row(@person, nickname: "Old Phone")

    assert_enqueued_email_with PasskeyMailer, :removed, params: { sender_id: @person.id },
                                                         args: [{ person: @person, nickname: "Old Phone", by: @person }] do
      delete me_profile_passkey_path(passkey)
    end
  end

  test "nothing is emailed about a passkey that was refused, or one that was never mine" do
    options = request_options
    theirs = add_passkey_row(@other, nickname: "Not Yours")

    assert_no_enqueued_emails do
      post me_profile_passkeys_path,
           params: { passkey_form: { credential: passkey_credential_for(options, user_verified: false) } }
      delete me_profile_passkey_path(theirs)
    end
  end

  # --- destroy ---

  test "removing my passkey removes it, says so, and is recorded" do
    passkey = add_passkey_row(@person, nickname: "Old Phone")
    ActionLog.delete_all

    assert_difference -> { @person.passkeys.count }, -1 do
      delete me_profile_passkey_path(passkey)
    end

    assert_redirected_to me_profile_passkeys_path
    assert_equal "Old Phone can no longer sign you in.", flash[:success]
    assert_equal @person.id, ActionLog.where(event: "person-passkey-delete").last.target_person_id
  end

  test "someone else's passkey is not mine to remove" do
    theirs = add_passkey_row(@other, nickname: "Not Yours")

    assert_no_difference -> { PersonPasskey.count } do
      delete me_profile_passkey_path(theirs)
    end

    assert_response :not_found
  end

  # --- the ways in ---

  test "the Account menu and the profile page both lead here" do
    get me_profile_path

    assert_response :success
    assert_select "a[href='#{me_profile_passkeys_path}']", text: /Passkeys/, minimum: 2
  end

  test "neither leads here on a Clubhouse that offers no passkeys" do
    switch_passkeys_off

    get me_profile_path

    assert_response :success
    assert_select "a[href='/me/profile/passkeys']", count: 0
    assert_select "a", text: /Change Password/, minimum: 1
  end

  # --- where passkeys are off ---

  test "a Clubhouse that offers no passkeys has no passkey pages" do
    switch_passkeys_off

    get me_profile_passkeys_path
    assert_response :not_found

    get new_me_profile_passkey_path
    assert_response :not_found

    post options_me_profile_passkeys_path, params: { passkey_form: { nickname: "x", current_password: "password" } }
    assert_response :not_found
  end

  private

  def request_options(nickname: "My Phone", current_password: "password")
    post options_me_profile_passkeys_path,
         params: { passkey_form: { nickname: nickname, current_password: current_password } }
    response.parsed_body
  end
end
