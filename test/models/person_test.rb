# frozen_string_literal: true

require "test_helper"

class PersonTest < ActiveSupport::TestCase
  include PersonTestFactory
  include TrainingSlotTestHelper

  # Renaming records the outgoing callsign as an FKA. Whether it stays
  # searchable is usually decided by its shape (PersonFka::IRRELEVANT_REGEXP),
  # but three status transitions override that -- see Person#fka_irrelevant_override.

  test "an active Ranger's old callsign stays searchable however it is shaped" do
    subject = person(:active_ranger)
    # A shape the regexp would otherwise bury, to prove the override wins.
    subject.update!(callsign: "PizzaBox25")
    subject.reload

    subject.update!(callsign: "Hubcap")

    fka = subject.person_fka.reload.find { |row| row.fka == "PizzaBox25" }
    assert_not_nil fka
    assert_equal false, fka.is_irrelevant,
                 "a plain rename keeps the old callsign findable even when it looks generated"
  end

  test "a PNV handle stays searchable when they become a past prospective" do
    subject = person(:prospective_ranger)
    subject.update!(callsign: "Kane25", status: Person::PROSPECTIVE)
    subject.reload

    subject.update!(callsign: "Hubcap", status: Person::PAST_PROSPECTIVE)

    fka = subject.person_fka.reload.find { |row| row.fka == "Kane25" }
    assert_not_nil fka
    assert_equal false, fka.is_irrelevant,
                 "the generated PNV handle is the only name the VC teams knew them by"
  end

  test "a past auditor's callsign is never searchable" do
    subject = person(:prospective_ranger)
    subject.update!(callsign: "Plainname", status: Person::AUDITOR)
    subject.reload

    subject.update!(callsign: "Hubcap", status: Person::PROSPECTIVE)

    fka = subject.person_fka.reload.find { |row| row.fka == "Plainname" }
    assert_not_nil fka
    assert fka.is_irrelevant, "past auditor callsigns are dropped regardless of shape"
  end

  # Both history hooks fire on update only: a new account has no previous
  # status or email, and both history tables reject a null one.

  test "creating an account writes no status or email history" do
    subject = nil

    assert_no_difference %w[PersonStatus.count EmailHistory.count] do
      subject = new_person
      assert subject.save, subject.errors.full_messages.join(", ")
    end

    subject.update!(status: Person::ACTIVE, email: "brandnew.moved@example.com")
    assert_equal 1, PersonStatus.where(person_id: subject.id).count
    assert_equal 1, EmailHistory.where(person_id: subject.id).count
  end

  test "a state is only required for countries that have one" do
    subject = new_person
    subject.state = ""

    subject.country = "US"
    assert_not subject.valid?
    assert_includes subject.errors[:state], "State can't be blank."

    subject.country = "GB"
    assert subject.valid?, subject.errors.full_messages.join(", ")
  end

  test "can_start_shift? blocks auditor, suspended, and deactivated statuses" do
    subject = Person.new

    Person::SHIFT_BLOCKED_STATUSES.each do |status|
      subject.status = status
      assert_not subject.can_start_shift?, "#{status} should be blocked"
    end

    # Alphas/Prospectives may start shifts (via a Mentor), as may Rangers.
    [Person::ACTIVE, Person::ALPHA, Person::PROSPECTIVE, Person::INACTIVE,
     Person::RETIRED, Person::ECHELON].each do |status|
      subject.status = status
      assert subject.can_start_shift?, "#{status} should be allowed"
    end
  end

  private

  # The password never reaches the action log, so a change is recorded on its
  # own -- otherwise the entry would carry nothing that names what happened.

  test "changing a password records it without recording the password" do
    subject = person(:active_ranger)
    Current.person = person(:inactive_ranger)

    assert_difference "ActionLog.where(event: 'auth-password-change').count", 1 do
      subject.password = "a-brand-new-password"
      subject.save!(validate: false)
    end

    entry = ActionLog.where(event: "auth-password-change", target_person_id: subject.id).last
    assert_equal "Password changed", entry.message
    assert_equal Current.person_id, entry.person_id
    assert_nil entry.data, "the password itself is never written down"
  end

  test "creating an account records no separate password change" do
    assert_no_difference "ActionLog.where(event: 'auth-password-change').count" do
      assert new_person.save
    end
  end

  test "the action log never carries a secret for a person" do
    %w[password sms_code].each do |column|
      assert_includes Person.audit_exclude, column
    end
  end

  test "only an Argon2 hash signs in" do
    subject = person(:active_ranger)
    subject.password = "password"
    subject.save!(validate: false)
    assert subject.authenticate("password")
    assert_not subject.authenticate("wrong")

    legacy = "0123456789abcdef:#{Digest::SHA1.hexdigest("0123456789abcdefpassword")}"
    subject.update_column(:password, legacy)
    assert_not subject.authenticate("password"), "a salted-SHA1 hash no longer verifies"
    assert_equal legacy, subject.reload.password, "and is not rewritten"

    subject.update_column(:password, "")
    assert_not subject.authenticate(""), "a retired password matches nothing, not even blank"
    assert_not subject.authenticate("password")
  end

  # Deleting an account is the one path that removes sign-ups and pod seats
  # outside the scheduling store and Pod's own methods, so the rows recount
  # their counters themselves.
  test "deleting an account recounts the shifts and pods it was on" do
    leaver = create_person("Leaver")
    slot = create_slot(positions(:ood_position), begins: Time.zone.local(2026, 8, 30, 12))
    sign_up(leaver, slot)
    sign_up(person(:active_ranger), slot)
    slot.update!(signed_up: 2)
    pod = Pod.create_alpha_set!(slot).sub_pods.find(&:alpha?)
    PersonPod.create!(pod:, person: leaver, sort_index: 1)
    pod.refresh_person_count!
    assert_equal 1, pod.reload.person_count

    leaver.destroy!

    assert_equal 1, slot.reload.signed_up
    assert_equal 0, pod.reload.person_count
    assert_not_nil pod.disbanded_at, "an emptied pod disbands"
  end

  def new_person
    Person.new(callsign: "Brandnew", first_name: "Brand", last_name: "New",
               email: "brandnew@example.com", status: Person::PROSPECTIVE,
               street1: "1 Example St", city: "Example City", state: "NV",
               zip: "99999", country: "US", home_phone: "775 555 0199",
               password: "not-a-real-password")
  end

  # --- phone numbers ---

  test "phone numbers are stored in E.164, read against the mailing address" do
    subject = new_person
    subject.country = "GB"
    subject.home_phone = "0121 496 0497 (home)"
    subject.alt_phone = "+1 775 555 0199"

    assert subject.valid?, subject.errors.full_messages.to_sentence
    assert_equal "+441214960497", subject.home_phone
    assert_equal "+17755550199", subject.alt_phone
  end

  test "a changed number that cannot be read is turned back as typed" do
    subject = person(:active_ranger)
    subject.home_phone = "775-555-JOAN"

    assert_not subject.valid?
    assert_equal [I18n.t("errors.messages.phone_invalid", attribute: "Primary phone")], subject.errors[:home_phone]
    assert_equal "775-555-JOAN", subject.home_phone
  end

  test "an alternative phone is held to the same rule, and may be cleared" do
    subject = person(:ranger_with_custom_gender)
    subject.alt_phone = "(775) 555-0199 cell"
    subject.country = "GB"

    assert_not subject.valid?, "a UK mobile or a Nevada number: refused, not guessed"
    assert_equal [I18n.t("errors.messages.phone_invalid", attribute: "Alternative phone")], subject.errors[:alt_phone]
    assert_equal "(775) 555-0199 cell", subject.alt_phone

    subject.reload.alt_phone = ""
    assert subject.save, subject.errors.full_messages.to_sentence
  end

  test "a number stored before numbers were checked never blocks another change" do
    subject = person(:active_ranger)
    subject.update_columns(home_phone: "555-555-5555")

    assert subject.update(camp_location: "3:00 & C"), subject.errors.full_messages.to_sentence
    assert_equal "555-555-5555", subject.reload.home_phone
  end

  # --- email addresses ---

  # Each passes Rails' pattern, but no mail could reach it (EmailAddresses.sendable?).
  test "an address no mail could reach is refused" do
    %w[a@b name@gmailcom a@1.2.3.4 a@b.123 a@b.c .a@example.com a..b@example.com a.@example.com].each do |address|
      subject = new_person
      subject.email = address

      assert_not subject.valid?, address
      assert_equal [I18n.t("errors.messages.email_invalid", attribute: "Email")], subject.errors[:email], address
    end
  end

  test "an address the pattern refuses is told so once" do
    subject = new_person
    subject.email = "invalid-email"

    assert_not subject.valid?
    assert_equal [I18n.t("errors.messages.email_invalid", attribute: "Email")], subject.errors[:email]
  end

  test "an address with dots and capitals in it is taken" do
    subject = new_person
    subject.email = "First.Last@Sub.Example.ORG"

    assert subject.valid?, subject.errors.full_messages.to_sentence
  end

  # Two ways such an address is on file: lowercase, as Clubhouse 3 stores every
  # address (update_columns runs the normalizer), and as Clubhouse 2 stored it,
  # as typed. The normalizer never reaches a value read back from the database.
  def people_with_stored_bad_addresses
    lowercase = person(:active_ranger)
    lowercase.update_columns(email: "ranger@gmailcom")
    legacy = person(:ranger_with_custom_gender)
    Person.where(id: legacy.id).update_all("email = 'Name@GmailCom'")

    [lowercase.reload, legacy.reload]
  end

  test "an address stored before addresses were checked never blocks another change" do
    lowercase, legacy = people_with_stored_bad_addresses

    assert lowercase.update(email: "Ranger@GmailCom"), lowercase.errors.full_messages.to_sentence
    assert lowercase.update(camp_location: "3:00 & C"), lowercase.errors.full_messages.to_sentence
    assert_equal "ranger@gmailcom", lowercase.reload.email

    # The identity form sends the address back on every save.
    assert_equal "Name@GmailCom", legacy.email
    assert legacy.update(email: legacy.email, camp_location: "3:00 & C"), legacy.errors.full_messages.to_sentence
    assert_equal "3:00 & C", legacy.reload.camp_location
  end

  test "a stored address no mail could reach may change only to one it can reach" do
    people_with_stored_bad_addresses.each do |subject|
      assert_not subject.update(email: "other@gmailcom"), subject.callsign
      assert_equal [I18n.t("errors.messages.email_invalid", attribute: "Email")], subject.errors[:email], subject.callsign

      subject.reload
      assert subject.update(email: "fixed-#{subject.id}@example.com"), subject.errors.full_messages.to_sentence
    end
  end

  # --- Paycom Employee ID ---

  test "a cleared employee id is stored as none, and a padded 0 as the 0" do
    subject = person(:active_ranger)

    subject.update!(employee_id: "  ")
    assert_nil subject.reload.employee_id

    subject.update!(employee_id: " 0\u00A0\u200B")
    assert_equal "0", subject.reload.employee_id
  end

  # --- names ---

  test "the full name uses the preferred name when there is one, with no stray space" do
    full_name = ->(**attrs) { Person.new(last_name: "Smith", **attrs).desired_full_name }

    assert_equal "Pat Smith", full_name.call(first_name: "Patricia", preferred_name: "Pat")
    assert_equal "Patricia Smith", full_name.call(first_name: "Patricia", preferred_name: "")
    assert_equal "Smith", full_name.call(first_name: "")
    assert_equal "Patricia", full_name.call(first_name: "Patricia", last_name: nil)
  end

  # --- single sign-on ---

  test "an sso token names the person for an hour and no longer" do
    subject = person(:active_ranger)
    token = subject.generate_token_for(:sso_access)

    assert_equal subject, Person.find_by_token_for(:sso_access, token)
    travel(Person::SSO_ACCESS_TOKEN_LIFETIME + 1.second) do
      assert_nil Person.find_by_token_for(:sso_access, token)
    end
    assert_nil Person.find_by_token_for(:sso_access, "made-up")
  end

  test "sso claims call an active Ranger a Ranger and anyone else by status" do
    ranger = person(:active_ranger)

    claims = ranger.sso_claims

    assert_equal({ sub: ranger.id.to_s, chid: ranger.id, username: ranger.callsign_normalized.downcase,
                   email: ranger.email, given_name: "Ranger", family_name: ranger.callsign }, claims)
    assert_equal "Prospective", person(:prospective_ranger).sso_claims[:given_name]
    # Retired counts as an active status, so the learning site still sees a Ranger.
    assert_equal "Ranger", person(:retired_ranger).sso_claims[:given_name]
  end
end
