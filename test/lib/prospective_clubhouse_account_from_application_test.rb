# frozen_string_literal: true

require "test_helper"

# Everything but Salesforce runs for real: the vetting rules, the account
# creation transaction, the callsign reassignment, the intake notes. Salesforce
# is a FakeSalesforceConnector, and most cases never build one at all -- the
# engine only reaches for a connector on a commit with writebacks enabled.
class ProspectiveClubhouseAccountFromApplicationTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include ActionMailer::TestHelper
  include ErrorLogTestHelper

  Creator = ProspectiveClubhouseAccountFromApplication

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
    Current.person = person(:auditor_ranger)
  end

  teardown do
    Current.reset
    travel_back
  end

  # ---- preview ----

  test "preview reports a clean application as ready and writes nothing" do
    application = prospective_application(:approved_ready)

    results = nil
    assert_no_difference(%w[Person.count PersonStatus.count PersonIntakeNote.count ActionLog.count]) do
      results = execute
    end

    assert_equal 1, results.size
    result = results.first
    assert_equal Creator::STATUS_READY, result.status
    assert_empty result.errors
    assert_equal application.id, result.application.id
    assert_nil result.created_person
    assert_equal ProspectiveApplication::STATUS_APPROVED, application.reload.status
  end

  test "only approved applications for the current year are considered" do
    prospective_application(:approved_ready).update!(year: 2025)

    assert_empty execute
  end

  # ---- required fields ----

  test "blank required fields are listed by name" do
    prospective_application(:approved_ready).update_columns(sfuid: "", phone: "")

    result = execute.first

    assert_equal Creator::STATUS_INVALID, result.status
    assert_match "Required fields are blank:", result.errors.first
    assert_match "Phone", result.errors.first
    assert_match "SFUID", result.errors.first
  end

  test "a state is required for the United States" do
    prospective_application(:approved_ready).update_columns(state: "")

    result = execute.first

    assert_equal Creator::STATUS_INVALID, result.status
    assert_match "State/Province", result.errors.first
  end

  # With a British phone: the fixture's "775 555 0104" reads as a number in
  # Britain as well as in North America, and the account refuses a guess.
  test "a state is not required outside the US, Canada, and Australia" do
    prospective_application(:approved_ready).update_columns(state: "", country: "GB", phone: "0121 496 0497")

    assert_equal Creator::STATUS_READY, execute.first.status
  end

  # ---- callsign conflicts ----

  test "an active account holding the callsign is a conflict" do
    holder = person(:active_ranger)
    prospective_application(:approved_ready).update_columns(approved_handle: holder.callsign)

    result = execute.first

    assert_equal Creator::STATUS_EXISTING_CALLSIGN, result.status
    assert_match "BPGUIDs do not match", result.errors.first
    assert_equal holder.id, result.conflicting_person.id
    assert_equal holder.callsign, result.conflicting_person.callsign
  end

  test "the applicant's own account does not conflict with itself" do
    holder = person(:auditor_ranger)
    holder.update_columns(bpguid: prospective_application(:approved_ready).bpguid)
    prospective_application(:approved_ready).update_columns(approved_handle: holder.callsign,
                                                 email: holder.email)

    result = execute.first

    assert_equal Creator::STATUS_READY, result.status
    assert_equal holder.id, result.existing_person.id
  end

  test "a vintage callsign is never reassigned" do
    holder = person(:retired_ranger)
    holder.update_columns(vintage: true)
    prospective_application(:approved_ready).update_columns(approved_handle: holder.callsign)

    result = execute.first

    assert_equal Creator::STATUS_EXISTING_CALLSIGN, result.status
    assert_match "vintage status", result.errors.first
  end

  test "a retired holder's callsign is marked for reassignment" do
    holder = person(:retired_ranger)
    prospective_application(:approved_ready).update_columns(approved_handle: holder.callsign)

    result = execute.first

    assert_equal Creator::STATUS_READY_REASSIGN_CALLSIGN, result.status
    assert_equal holder.id, result.reassign_callsign.id
  end

  test "a deceased holder with no status history blocks the callsign" do
    holder = person(:retired_ranger)
    holder.update_columns(status: Person::DECEASED)
    prospective_application(:approved_ready).update_columns(approved_handle: holder.callsign)

    result = execute.first

    assert_equal Creator::STATUS_EXISTING_CALLSIGN, result.status
    assert_match "cannot determine if still within the grieving period", result.errors.first
  end

  test "a deceased holder inside the grieving period blocks the callsign" do
    holder = deceased_holder(died_at: 2.years.ago)
    prospective_application(:approved_ready).update_columns(approved_handle: holder.callsign)

    result = execute.first

    assert_equal Creator::STATUS_EXISTING_CALLSIGN, result.status
    assert_match "still in the grieving period of 5 years", result.errors.first
  end

  test "a deceased holder past the grieving period releases the callsign" do
    holder = deceased_holder(died_at: 6.years.ago)
    prospective_application(:approved_ready).update_columns(approved_handle: holder.callsign)

    result = execute.first

    assert_equal Creator::STATUS_READY_REASSIGN_CALLSIGN, result.status
    assert_equal holder.id, result.reassign_callsign.id
  end

  # ---- reserved handles ----

  test "a reserved handle blocks the application" do
    prospective_application(:approved_ready)
      .update_columns(approved_handle: handle_reservation(:ranger_term).handle)

    result = execute.first

    assert_equal Creator::STATUS_RESERVED_CALLSIGN, result.status
    assert_match "Is a reserved handle/word (Ranger term)", result.errors.first
  end

  test "an expired reservation does not block the application" do
    prospective_application(:approved_ready)
      .update_columns(approved_handle: handle_reservation(:expiring).handle)

    assert_equal Creator::STATUS_READY, execute.first.status
  end

  test "an applicant who already holds the reserved handle is not blocked" do
    holder = person(:auditor_ranger)
    handle_reservation(:ranger_term).update_columns(
      handle: holder.callsign,
      normalized_handle: WordUtils.normalize_word(holder.callsign)
    )
    application = prospective_application(:approved_ready)
    holder.update_columns(bpguid: application.bpguid)
    application.update_columns(approved_handle: holder.callsign, email: holder.email)

    result = execute.first

    assert_equal Creator::STATUS_READY, result.status
    assert_empty result.errors
    assert_equal holder.id, result.existing_person.id
  end

  # ---- duplicate identity ----

  test "an existing account with an unusable status is a conflict" do
    existing = person(:active_ranger)
    prospective_application(:approved_ready).update_columns(email: existing.email)

    result = execute.first

    assert_equal Creator::STATUS_EXISTING_BAD_STATUS, result.status
    assert_match "Account with the same email already exists", result.errors.first
    assert_equal existing.id, result.conflicting_person.id
  end

  test "an email and BPGUID matching two different accounts is a conflict" do
    by_email = person(:auditor_ranger)
    by_bpguid = person(:echelon_ranger)
    by_bpguid.update_columns(bpguid: "ECHELON-BPGUID-0001")
    prospective_application(:approved_ready).update_columns(email: by_email.email, bpguid: by_bpguid.bpguid)

    result = execute.first

    assert_equal Creator::STATUS_EXISTING_BAD_STATUS, result.status
    assert_match "two different existing accounts", result.errors.first
  end

  # A returning applicant who changed email addresses since their last account.
  test "an existing account matching by BPGUID alone is converted" do
    existing = person(:auditor_ranger)
    application = prospective_application(:approved_ready)
    existing.update_columns(bpguid: application.bpguid)
    assert_not_equal existing.email, application.email

    results = nil
    assert_no_difference "Person.count" do
      results = execute(commit: true)
    end

    result = results.first
    assert_equal Creator::STATUS_CREATED, result.status
    assert_equal existing.id, result.person_id
    assert_equal application.email, existing.reload.email
  end

  # ---- the account's own rules ----

  # The preview builds the account a commit would save and runs Person's
  # validations on it, so a value the account refuses shows before anyone
  # presses Create Accounts, named by the application field it came from.
  {
    "a phone that is not a phone number" => [{ phone: "775-555-JOAN" }, I18n.t("errors.messages.phone_invalid", attribute: "Phone")],
    "a last name too long for an account" => [{ last_name: "x" * 26 },
                                              "Last Name is too long (maximum is 25 characters)."]
  }.each do |what, (columns, message)|
    test "the preview finds #{what}" do
      application = prospective_application(:approved_ready)
      application.update_columns(columns)

      results = nil
      assert_no_difference(%w[Person.count PersonStatus.count ActionLog.count ErrorLog.count]) do
        results = execute
      end

      result = results.first
      assert_equal Creator::STATUS_INVALID, result.status
      assert_equal [message], result.errors
      assert_no_match(/home_phone|email:|last_name/, result.errors.first)
      assert_equal ProspectiveApplication::STATUS_APPROVED, application.reload.status
    end
  end

  # callsign_normalized is not unique, so the account retrieve_by_callsign
  # marks for reassignment may not be the one holding the exact callsign.
  # Taking the callsign from "Sun Burst" would not free "Sunburst".
  test "an exact holder beside the account being reassigned is a callsign conflict" do
    reassigned, holder = [person(:retired_ranger), person(:active_ranger)].sort_by(&:id)
    reassigned.update_columns(callsign: "Sun Burst", callsign_normalized: "sunburst", status: Person::RETIRED)
    holder.update_columns(callsign: "Sunburst", callsign_normalized: "sunburst", status: Person::ACTIVE)
    assert_equal reassigned.id, Person.retrieve_by_callsign("Sunburst").id,
                 "the lookup has no ORDER BY; were the holder found, this would test the plain conflict"

    result = execute.first

    assert_equal Creator::STATUS_EXISTING_CALLSIGN, result.status
    assert_equal ["Callsign conflict with the account shown, which already holds this exact callsign."],
                 result.errors
    assert_equal holder.id, result.conflicting_person.id

    assert_no_difference "Person.count" do
      assert_equal Creator::STATUS_EXISTING_CALLSIGN, execute(commit: true).first.status
    end
    assert_equal "Sun Burst", reassigned.reload.callsign
    assert_equal "Sunburst", holder.reload.callsign
  end

  # bpguid is not unique either. The account holding the callsign passes
  # detect_callsign_conflict as the applicant's own, while find_by(bpguid)
  # picks another account with the same BPGUID to convert.
  test "a duplicate BPGUID holding the callsign is a callsign conflict" do
    application = prospective_application(:approved_ready)
    converted, holder = [person(:auditor_ranger), person(:active_ranger)].sort_by(&:id)
    converted.update_columns(status: Person::AUDITOR, bpguid: application.bpguid)
    holder.update_columns(status: Person::ACTIVE, callsign: "Sunburst", callsign_normalized: "sunburst",
                          bpguid: application.bpguid)
    assert_equal converted.id, Person.find_by(bpguid: application.bpguid).id,
                 "the lookup has no ORDER BY; were the holder found, this would test the bad-status conflict"

    result = execute.first

    assert_equal Creator::STATUS_EXISTING_CALLSIGN, result.status
    assert_equal holder.id, result.conflicting_person.id
  end

  # A converted account keeps every stored value the application does not
  # overwrite, and Person checks those too. The fix is made on that account,
  # so the message names it.
  test "a converted account's own value the account refuses names that account" do
    existing = match_existing_account(person(:auditor_ranger))
    existing.update_columns(callsign_pronounce: "x" * 21)

    result = execute.first

    assert_equal Creator::STATUS_INVALID, result.status
    assert_equal ["Existing account ##{existing.id}: Pronunciation is too long (maximum is 20 characters)."],
                 result.errors
    assert_no_match(/callsign_pronounce/, result.errors.first)
  end

  # ---- creating accounts ----

  test "a commit creates the account and marks the application created" do
    application = prospective_application(:approved_ready)

    results = nil
    assert_difference "Person.count", 1 do
      results = execute(commit: true)
    end

    result = results.first
    assert_equal Creator::STATUS_CREATED, result.status
    assert_empty result.errors

    created = Person.find(result.person_id)
    assert_equal "Sunburst", created.callsign
    assert created.callsign_approved?
    assert_equal Person::PROSPECTIVE, created.status
    assert_equal "Sunny", created.first_name
    assert_equal "4 Example St", created.street1
    assert_equal "99999", created.zip
    assert_equal "+17755550104", created.home_phone
    assert_equal "005SF9001", created.sfuid
    assert_equal "Dusty Trails", created.known_rangers
    assert_equal "River Stone", created.known_pnvs

    application.reload
    assert_equal ProspectiveApplication::STATUS_CREATED, application.status
    assert_equal created.id, application.person_id

    status = PersonStatus.where(person_id: created.id).last
    assert_equal "", status.old_status
    assert_equal Person::PROSPECTIVE, status.new_status
    assert_equal "application approved", status.reason
  end

  test "the placeholder password can never be guessed" do
    created = Person.find(execute(commit: true).first.person_id)

    assert_not created.authenticate("abcdef")
    assert_not created.authenticate("")
  end

  test "application notes are copied as VC intake notes" do
    application = prospective_application(:approved_ready)
    application.notes.create!(note: "Strong references.", type: "vc", person_id: person(:active_ranger).id)
    application.notes.create!(note: "Imported from Salesforce.", type: "vc", person_id: nil)

    result = execute(commit: true).first

    notes = PersonIntakeNote.where(person_id: result.person_id).order(:id)
    assert_equal 2, notes.size
    assert_equal %w[vc vc], notes.map(&:type)
    assert_equal [2026, 2026], notes.map(&:year)
    assert_equal "Strong references.", notes.first.note
    assert_equal person(:active_ranger).id, notes.first.person_source_id
    assert_equal Current.person_id, notes.last.person_source_id, "authorless notes fall back to the operator"
  end

  test "a commit reassigns a retired holder's callsign" do
    holder = person(:retired_ranger)
    original_callsign = holder.callsign
    prospective_application(:approved_ready).update_columns(approved_handle: original_callsign)

    result = execute(commit: true).first

    assert_equal Creator::STATUS_CREATED, result.status
    assert_equal original_callsign, Person.find(result.person_id).callsign
    assert_not_equal original_callsign, holder.reload.callsign
    assert PersonFka.exists?(person_id: holder.id, fka: original_callsign)
  end

  test "an eligible existing account is converted rather than duplicated" do
    existing = match_existing_account(person(:auditor_ranger))

    results = nil
    assert_no_difference "Person.count" do
      results = execute(commit: true)
    end

    result = results.first
    assert_equal Creator::STATUS_CREATED, result.status
    assert_equal existing.id, result.person_id

    existing.reload
    assert_equal Person::PROSPECTIVE, existing.status
    assert_equal "Sunburst", existing.callsign

    status = PersonStatus.where(person_id: existing.id).last
    assert_equal Person::AUDITOR, status.old_status
    assert_equal Person::PROSPECTIVE, status.new_status
  end

  test "the batch continues past an application the account would refuse" do
    broken = duplicate_application(email: "windward@example.com", handle: "Windward")
    broken.update_columns(last_name: "x" * 26)

    results = nil
    silence_error_log do |calls|
      assert_difference "Person.count", 1 do
        results = execute(commit: true)
      end
      assert_empty calls
    end

    failed = results.find { |result| result.application.id == broken.id }
    assert_equal Creator::STATUS_INVALID, failed.status
    assert_equal ["Last Name is too long (maximum is 25 characters)."], failed.errors
    assert_equal ProspectiveApplication::STATUS_APPROVED, broken.reload.status

    other = results.find { |result| result.application.id != broken.id }
    assert_equal Creator::STATUS_CREATED, other.status
  end

  # A commit runs the account's own rules before it saves, as the preview
  # does: a phone the account would refuse leaves the application invalid,
  # a fix for the VCs, never a creation failure for the Tech Cadre. Nothing
  # is saved or logged, and the application stays approved.
  test "an application phone that is not a phone number is invalid at commit" do
    application = prospective_application(:approved_ready)
    application.update_columns(phone: "775-555-JOAN")

    results = nil
    assert_no_difference "Person.count" do
      silence_error_log do |calls|
        results = execute(commit: true)
        assert_empty calls
      end
    end

    failed = results.find { |result| result.application.id == application.id }
    assert_equal Creator::STATUS_INVALID, failed.status
    assert_equal [I18n.t("errors.messages.phone_invalid", attribute: "Phone")], failed.errors
    assert_equal ProspectiveApplication::STATUS_APPROVED, application.reload.status
  end

  # So does an email no mail could reach, imported from Salesforce.
  test "an application email no mail could reach is invalid at commit" do
    application = prospective_application(:approved_ready)
    application.update_columns(email: "name@gmailcom")

    results = nil
    assert_no_difference "Person.count" do
      silence_error_log do |calls|
        results = execute(commit: true)
        assert_empty calls
      end
    end

    failed = results.find { |result| result.application.id == application.id }
    assert_equal Creator::STATUS_INVALID, failed.status
    assert_equal [I18n.t("errors.messages.email_invalid", attribute: "Email")], failed.errors
    assert_equal ProspectiveApplication::STATUS_APPROVED, application.reload.status
  end

  # Pins the column-limit gap: Person allows a 191-character city, the column
  # holds 50, and a limit that is not a validation passes valid?. So the
  # preview says ready, and the save fails as an SQL error for the Tech Cadre.
  # A fix that moves the column limits into Person makes this invalid instead.
  test "a value too long for its column previews ready and fails at commit" do
    application = prospective_application(:approved_ready)
    application.update_columns(city: "x" * 51)

    assert_equal Creator::STATUS_READY, execute.first.status

    results = nil
    assert_no_difference "Person.count" do
      silence_error_log do |calls|
        results = execute(commit: true)
        assert_equal [[:record_exception, "application-account-fail"]],
                     calls.map { |call| [call[:method], call[:args][1]] }
      end
    end

    failed = results.first
    assert_equal Creator::STATUS_CREATE_FAILED, failed.status
    assert_match(/\ASQL Error:/, failed.errors.first)
    assert_equal ProspectiveApplication::STATUS_APPROVED, application.reload.status
  end

  # ---- welcome email ----

  test "the welcome email is sent when the setting is on" do
    enable(Setting::SEND_WELCOME_EMAIL)

    assert_enqueued_emails 1 do
      execute(commit: true)
    end
  end

  # Queued, so the job that sends it has nobody signed in: the VC who made the
  # account travels with it. The invite link signs its holder in, so the log
  # keeps none of the text.
  test "the welcome email is logged under whoever made the account, without its text" do
    enable(Setting::SEND_WELCOME_EMAIL)
    execute(commit: true)
    Current.person = nil

    perform_enqueued_jobs

    created = Person.find_by!(email: prospective_application(:approved_ready).email)
    row = MailLog.find_by!(person_id: created.id)
    assert_equal person(:auditor_ranger).id, row.sender_id
    assert row.body_withheld?
  end

  test "no welcome email is sent when the setting is off" do
    assert_enqueued_emails 0 do
      execute(commit: true)
    end
  end

  # ---- action log ----

  test "the action log summary carries no applicant details" do
    assert_difference 'ActionLog.where(event: "prospective-account-create").count', 1 do
      execute(commit: true)
    end

    log = ActionLog.where(event: "prospective-account-create").last
    assert_equal 1, log.data["results"].size
    assert_equal Creator::STATUS_CREATED, log.data["results"].first["status"]
    assert_not log.data["sent_welcome_emails"]

    serialized = log.data.to_json
    assert_no_match(/sunny\.approved/, serialized)
    assert_no_match(/Sunburst/, serialized)
  end

  test "a preview writes no action log" do
    assert_no_difference 'ActionLog.where(event: "prospective-account-create").count' do
      execute
    end
  end

  # ---- Salesforce ----

  # The dev database holds live production Salesforce credentials, so a preview
  # must never build a connector even with writebacks enabled.
  test "a preview never contacts Salesforce" do
    enable(Setting::SF_ENABLE_WRITEBACKS)
    fake = FakeSalesforceConnector.new
    fake.define_singleton_method(:auth) { raise "Salesforce must not be contacted" }

    original = Salesforce.method(:connector)
    Salesforce.define_singleton_method(:connector) { raise "no connector may be built for a preview" }
    begin
      results = execute(connector: fake)
    ensure
      Salesforce.define_singleton_method(:connector, original)
    end

    assert_equal Creator::STATUS_READY, results.first.status
    assert_empty fake.updates
  end

  test "the connector is never touched when writebacks are off" do
    fake = FakeSalesforceConnector.new
    fake.define_singleton_method(:auth) { raise "Salesforce must not be contacted" }

    results = execute(commit: true, connector: fake)

    assert_equal Creator::STATUS_CREATED, results.first.status
    assert_empty fake.updates
  end

  test "a commit writes the account back to Salesforce" do
    enable(Setting::SF_ENABLE_WRITEBACKS)
    fake = FakeSalesforceConnector.new

    result = execute(commit: true, connector: fake).first

    assert_equal 1, fake.updates.size
    update = fake.updates.first
    assert_equal "Ranger__c", update[:objname]
    assert_equal "a01SF9001", update[:objid]
    assert_equal result.person_id.to_s, update[:fields]["CH_UID__c"]
    assert_equal "Sunburst", update[:fields]["VC_Approved_Radio_Call_Sign__c"]
    assert_equal "2026", update[:fields]["VC_Event_Year__c"]
    assert_equal "Clubhouse Record Created", update[:fields]["VC_Status__c"]
    assert_match "successfully created", update[:fields]["CH_ImportStatusMessage__c"]
  end

  test "converting an existing account reports an update to Salesforce" do
    enable(Setting::SF_ENABLE_WRITEBACKS)
    match_existing_account(person(:auditor_ranger))
    fake = FakeSalesforceConnector.new

    execute(commit: true, connector: fake)

    assert_equal "Clubhouse Record Updated", fake.updates.first[:fields]["VC_Status__c"]
  end

  test "a failed writeback rolls back that account but not the batch" do
    enable(Setting::SF_ENABLE_WRITEBACKS)
    holder = person(:retired_ranger)
    original_callsign = holder.callsign
    prospective_application(:approved_ready).update_columns(approved_handle: original_callsign)
    second = duplicate_application(email: "second.approved@example.com", handle: "Leeward")
    fake = FakeSalesforceConnector.new(update_results: [false, true])

    results = nil
    silence_error_log do
      assert_difference "Person.count", 1, "only the second account survives" do
        results = execute(commit: true, connector: fake)
      end
    end

    failed = results.find { |result| result.application.id == prospective_application(:approved_ready).id }
    assert_equal Creator::STATUS_CREATE_FAILED, failed.status
    assert_match "Salesforce record update failure", failed.errors.first
    assert_equal ProspectiveApplication::STATUS_APPROVED, prospective_application(:approved_ready).reload.status
    assert_equal original_callsign, holder.reload.callsign, "the reassignment rolled back too"
    assert_nil Person.find_by(email: "sunny.approved@example.com")

    survivor = results.find { |result| result.application.id == second.id }
    assert_equal Creator::STATUS_CREATED, survivor.status
  end

  test "a Salesforce sign-in failure abandons the whole batch" do
    enable(Setting::SF_ENABLE_WRITEBACKS)
    fake = FakeSalesforceConnector.new(auth_result: false)

    batch = nil
    assert_no_difference ["Person.count", 'ActionLog.where(event: "prospective-account-create").count'] do
      batch = Creator.execute(commit: true, connector: fake)
    end

    assert batch.auth_failure?
    assert_equal fake.error_message, batch.auth_error
    assert_nil batch.results
    assert_equal ProspectiveApplication::STATUS_APPROVED, prospective_application(:approved_ready).reload.status
  end

  private

  def execute(commit: false, connector: nil)
    batch = Creator.execute(commit:, connector:)
    assert_not batch.auth_failure?, "unexpected Salesforce auth failure"
    batch.results
  end

  def enable(setting)
    Setting.create!(name: setting, value: "true")
  end

  # A second approved application, so batch-level behavior can be observed.
  def duplicate_application(email:, handle:)
    prospective_application(:approved_ready).dup.tap do |application|
      application.email = email
      application.approved_handle = handle
      application.bpguid = "APPLICANT-BPGUID-#{handle}"
      application.salesforce_id = "a01SF#{handle}"
      application.save!(validate: false)
    end
  end

  # Point the application at an existing account by both email and BPGUID.
  def match_existing_account(existing)
    application = prospective_application(:approved_ready)
    existing.update_columns(bpguid: application.bpguid)
    application.update_columns(email: existing.email)
    existing
  end

  def deceased_holder(died_at:)
    holder = person(:retired_ranger)
    holder.update_columns(status: Person::DECEASED)
    PersonStatus.create!(person_id: holder.id, person_source_id: Current.person_id,
                         old_status: Person::RETIRED, new_status: Person::DECEASED,
                         reason: "test", created_at: died_at)
    holder
  end
end
