# frozen_string_literal: true

require "test_helper"

# The Salesforce pull itself is faked (FakeSalesforceConnector); everything
# from the SOQL text through the mapped rows, buckets, and DB writes runs for
# real. Ports the Laravel ProspectiveApplicationImportTest cases plus the
# mapping rules that suite never covered.
class ProspectiveApplicationImportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include ErrorLogTestHelper

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
    Current.person = person(:auditor_ranger)
  end

  teardown do
    Current.reset
    travel_back
  end

  # ---- mapping and preview ----

  test "preview maps a clean application and saves nothing" do
    fake = fake_connector(
      [FakeSalesforceConnector.application_record(
        "VC_Approved_Radio_Call_Sign__c" => "Dustoff (2019)",
        "CH_UID__c" => ""
      )],
      [FakeSalesforceConnector.contact_record(
        "a01SF001",
        "MailingStreet" => "1 Example St\r\nApt 9",
        "Phone" => "",
        "MobilePhone" => "  775-555-0142  ",
        "Emergency_Contact_Name__c" => "Moon Beam",
        "Emergency_Contact_Phone__c" => "775-555-0199",
        "Emergency_Contact_Relationship__c" => "partner"
      )]
    )

    import = nil
    assert_no_difference(%w[ProspectiveApplication.count ProspectiveApplicationLog.count
                            ProspectiveApplicationNote.count]) do
      import = run_import(fake, commit: false)
    end

    assert_equal 1, import.new_applications.length
    assert_empty import.existing_applications
    assert_empty import.query_failures
    assert_empty import.create_failures
    assert_nil import.api_error

    row = import.new_applications.first
    assert_not row.persisted?
    assert_equal "a01SF001", row.salesforce_id
    assert_equal "R-5001", row.salesforce_name
    assert_equal "Terra", row.first_name
    assert_equal "Firma", row.last_name
    assert_equal "terra.firma@example.com", row.email
    assert_equal "SF-BPGUID-5001", row.bpguid
    # The Salesforce event year (2031) is ignored; imports land in the
    # current event year.
    assert_equal 2026, row.year
    assert_nil row.person_id
    assert_equal ProspectiveApplication::STATUS_PENDING, row.status
    assert_equal ProspectiveApplication::WHY_VOLUNTEER_REVIEW_UNREVIEWED, row.why_volunteer_review
    assert_equal ProspectiveApplication::EXPERIENCE_BRC2, row.experience
    assert row.is_over_18
    # Contact-derived fields.
    assert_equal "1 Example St Apt 9", row.street
    assert_equal "Example City", row.city
    assert_equal "005SF001", row.sfuid
    assert_equal "775-555-0142", row.phone
    assert_equal "Moon Beam (partner) phone 775-555-0199", row.emergency_contact
    # Recycled "Handle (YYYY)" approvals are blanked.
    assert_equal "", row.approved_handle
  end

  test "commit saves the application with its audit log entry and notes" do
    fake = fake_connector(
      [FakeSalesforceConnector.application_record(
        "VC_Comments__c" => "Looks solid.",
        "Why_Ranger_Comments__c" => "Wants to give back."
      )],
      [FakeSalesforceConnector.contact_record("a01SF001")]
    )

    import = nil
    assert_difference "ProspectiveApplication.count", 1 do
      assert_difference "ProspectiveApplicationLog.count", 1 do
        assert_difference "ProspectiveApplicationNote.count", 2 do
          import = run_import(fake, commit: true)
        end
      end
    end

    row = import.new_applications.first
    assert row.persisted?

    log = ProspectiveApplicationLog.where(prospective_application_id: row.id).last
    assert_equal ProspectiveApplicationLog::ACTION_IMPORTED, log.action
    assert_equal "Not Yet Started", log.data["salesforce_status"]
    assert_equal "Prospective New Volunteer - Black Rock Ranger", log.data["salesforce_type"]
    assert_equal Current.person_id, log.person_id

    notes = ProspectiveApplicationNote.where(prospective_application_id: row.id).order(:id)
    assert_equal [ProspectiveApplicationNote::TYPE_VC, ProspectiveApplicationNote::TYPE_VC_COMMENT],
                 notes.map(&:type)
    assert_equal ["Looks solid.", "Wants to give back."], notes.map(&:note)
    assert notes.all? { |note| note.person_id.nil? }, "imported notes carry no author"
  end

  test "an application already in the Clubhouse lands in the existing bucket" do
    existing = prospective_application(:pending_qualified)
    fake = fake_connector(
      [FakeSalesforceConnector.application_record("Name" => existing.salesforce_name)],
      [FakeSalesforceConnector.contact_record("a01SF001")]
    )

    import = nil
    assert_no_difference "ProspectiveApplication.count" do
      import = run_import(fake, commit: true)
    end

    assert_empty import.new_applications
    assert_equal [existing.id], import.existing_applications.map(&:id)
  end

  # ---- per-record query failures ----

  test "a contact missing from the batched lookup is a query failure" do
    fake = fake_connector(
      [FakeSalesforceConnector.application_record],
      [] # USER_MODE hid the contact
    )

    import = run_import(fake, commit: true)

    assert_empty import.new_applications
    failure = import.query_failures.first
    assert_equal :contact_inaccessible, failure.error
    assert_equal "Contact record is inaccessible", failure.label
    assert_equal "R-5001", failure.application.salesforce_name
    assert_nil import.api_error
  end

  test "a null Ranger_Info__r relationship is a query failure" do
    fake = fake_connector(
      [FakeSalesforceConnector.application_record],
      [FakeSalesforceConnector.contact_record_without_ranger_info("a01SF001")]
    )

    import = run_import(fake, commit: false)
    assert_equal :contact_inaccessible, import.query_failures.first.error
  end

  test "a contact with every mapped field blank is a query failure" do
    blank_fields = {
      "Years_Attended_Burning_Man__c" => "", "MailingStreet" => "", "MailingCity" => "",
      "MailingState" => "", "MailingCountry" => "", "MailingPostalCode" => "", "SFUID__c" => "",
      # Query-only fields do not count toward the blank check.
      "Phone" => "775-555-0177"
    }
    fake = fake_connector(
      [FakeSalesforceConnector.application_record],
      [FakeSalesforceConnector.contact_record("a01SF001", blank_fields)]
    )

    import = run_import(fake, commit: false)

    failure = import.query_failures.first
    assert_equal :contact_blank, failure.error
    assert_equal "003a01SF001", failure.contact_id
  end

  test "a blank BPGUID with no Clubhouse account is a query failure" do
    fake = fake_connector(
      [FakeSalesforceConnector.application_record("Applicant_BPGUID__c" => "", "CH_UID__c" => "")],
      [FakeSalesforceConnector.contact_record("a01SF001")]
    )

    import = run_import(fake, commit: true)

    assert_equal :missing_bpguid, import.query_failures.first.error
    assert_equal "BPGUID is missing or inaccessible", import.query_failures.first.label
  end

  test "a blank BPGUID is backfilled from the linked Clubhouse account" do
    person = person(:active_ranger)
    person.update_columns(bpguid: "BACKFILL-GUID-1")

    fake = fake_connector(
      [FakeSalesforceConnector.application_record(
        "Applicant_BPGUID__c" => "", "CH_UID__c" => person.id.to_s
      )],
      [FakeSalesforceConnector.contact_record("a01SF001")]
    )

    import = run_import(fake, commit: false)

    row = import.new_applications.first
    assert_equal "BACKFILL-GUID-1", row.bpguid
    assert_equal person.id, row.person_id
  end

  # ---- batched contact lookup ----

  test "contacts are fetched in one batched query per page" do
    records = %w[a01 a02 a03].map.with_index do |id, index|
      FakeSalesforceConnector.application_record("Id" => id, "Name" => "R-51#{index}")
    end
    contacts = [
      FakeSalesforceConnector.contact_record("a01"),
      # a02 is absent (inaccessible)
      FakeSalesforceConnector.contact_record("a03", "MailingStreet" => "", "MailingCity" => "",
                                                    "MailingState" => "", "MailingCountry" => "",
                                                    "MailingPostalCode" => "", "SFUID__c" => "",
                                                    "Years_Attended_Burning_Man__c" => "")
    ]
    fake = fake_connector(records, contacts)

    import = run_import(fake, commit: false)

    assert_equal 3, fake.queries.length, "list page, contact batch, empty second page"
    contact_query = fake.queries[1]
    assert_includes contact_query, "Id IN ('a01','a02','a03')"
    assert_includes contact_query, "WITH USER_MODE"

    assert_equal 1, import.new_applications.length
    assert_equal [:contact_inaccessible, :contact_blank].sort, import.query_failures.map(&:error).sort
  end

  test "contact ids are quoted against embedded quotes" do
    fake = fake_connector(
      [FakeSalesforceConnector.application_record("Id" => "a'01")],
      []
    )

    run_import(fake, commit: false)

    assert_includes fake.queries[1], %q(Id IN ('a\\'01'))
  end

  test "a failed contact batch marks the whole page inaccessible without an api error" do
    records = [
      FakeSalesforceConnector.application_record("Id" => "a01", "Name" => "R-5101"),
      FakeSalesforceConnector.application_record("Id" => "a02", "Name" => "R-5102")
    ]
    fake = FakeSalesforceConnector.new(query_results: [FakeSalesforceConnector.envelope(*records), false])

    import = run_import(fake, commit: true)

    assert_equal %i[contact_inaccessible contact_inaccessible], import.query_failures.map(&:error)
    assert_nil import.api_error, "a contact batch failure must not stop the run"
  end

  # ---- run-level failures ----

  test "a failed list query stops pagination but keeps earlier results" do
    fake = FakeSalesforceConnector.new(
      query_results: [
        FakeSalesforceConnector.envelope(FakeSalesforceConnector.application_record),
        FakeSalesforceConnector.envelope(FakeSalesforceConnector.contact_record("a01SF001")),
        false # second list page dies
      ]
    )

    import = run_import(fake, commit: false)

    assert_equal 1, import.new_applications.length, "page one results survive"
    assert_equal "fake salesforce failure", import.api_error
  end

  test "auth failures pass the connector message through" do
    fake = FakeSalesforceConnector.new(auth_result: false)
    import = ProspectiveApplicationImport.new(connector: fake)

    assert_not import.auth
    assert_equal "fake salesforce failure", import.auth_error
  end

  # ---- commit failures ----

  test "a validation failure lands in create failures with a scrubbed error log" do
    fake = fake_connector(
      [FakeSalesforceConnector.application_record("Contact_Email__c" => "")],
      [FakeSalesforceConnector.contact_record("a01SF001")]
    )

    import = nil
    silence_error_log do |calls|
      assert_no_difference "ProspectiveApplication.count" do
        import = run_import(fake, commit: true)
      end

      call = calls.find { |c| c[:type] == "prospective-application-validation-failure" }
      assert call, "expected a validation-failure error log"
      record = call[:kwargs][:data][:record]
      assert_equal({ salesforce_id: "a01SF001", salesforce_name: "R-5001" }, record)
    end

    failure = import.create_failures.first
    assert_equal :invalid, failure.error
    assert_match "Fields failed to validate", failure.message
    assert_match "email", failure.message
    assert_empty import.new_applications
  end

  test "an exception after save rolls the record back and the run continues" do
    records = [
      FakeSalesforceConnector.application_record("Id" => "a01", "Name" => "R-5101",
                                                 "Contact_Email__c" => "first@example.com"),
      FakeSalesforceConnector.application_record("Id" => "a02", "Name" => "R-5102",
                                                 "Contact_Email__c" => "second@example.com")
    ]
    contacts = [FakeSalesforceConnector.contact_record("a01"), FakeSalesforceConnector.contact_record("a02")]
    fake = fake_connector(records, contacts)

    original = ProspectiveApplicationLog.method(:record)
    first_call = true
    ProspectiveApplicationLog.define_singleton_method(:record) do |*args|
      if first_call
        first_call = false
        raise "simulated log failure for first@example.com"
      end
      original.call(*args)
    end

    import = nil
    begin
      silence_error_log do |calls|
        assert_difference "ProspectiveApplication.count", 1 do
          import = run_import(fake, commit: true)
        end

        call = calls.find { |c| c[:type] == "prospective-application-create-failure" }
        assert call, "expected a create-failure error log"
        logged = call[:kwargs].to_json
        assert_no_match(/first@example\.com/, logged, "error log must not carry the exception message")
        assert_equal "RuntimeError", call[:kwargs][:data][:exception][:class]
      end
    ensure
      ProspectiveApplicationLog.define_singleton_method(:record, original)
    end

    failure = import.create_failures.first
    assert_equal :create_failure, failure.error
    assert_match "first@example.com", failure.message, "the page keeps the full detail"
    assert_equal "R-5101", failure.application.salesforce_name

    assert_not ProspectiveApplication.exists?(year: 2026, salesforce_name: "R-5101"), "rolled back"
    assert ProspectiveApplication.exists?(year: 2026, salesforce_name: "R-5102"), "run continued"
    assert_equal ["R-5102"], import.new_applications.map(&:salesforce_name)
  end

  # ---- pure mapping helpers ----

  test "status_for maps View 1 statuses and falls back to pending" do
    assert_equal ProspectiveApplication::STATUS_PENDING,
                 ProspectiveApplicationImport.status_for("Not Yet Started", nil)
    assert_equal ProspectiveApplication::STATUS_APPROVED,
                 ProspectiveApplicationImport.status_for("Released to Upload", nil)
    assert_equal ProspectiveApplication::STATUS_REJECT_UBERBONKED,
                 ProspectiveApplicationImport.status_for("STOP - UBERBONK", nil)
    assert_equal ProspectiveApplication::STATUS_PENDING,
                 ProspectiveApplicationImport.status_for("Brand New Picklist Value", nil)
  end

  test "status_for special-cases STOP - Past Prospective on the linked account" do
    assert_equal ProspectiveApplication::STATUS_CREATED,
                 ProspectiveApplicationImport.status_for("STOP - Past Prospective", 99)
    assert_equal ProspectiveApplication::STATUS_PENDING,
                 ProspectiveApplicationImport.status_for("STOP - Past Prospective", nil)
  end

  test "experience_for maps known values and falls back to none" do
    assert_equal ProspectiveApplication::EXPERIENCE_BRC1, ProspectiveApplicationImport.experience_for("Yes")
    assert_equal ProspectiveApplication::EXPERIENCE_BRC1R1,
                 ProspectiveApplicationImport.experience_for("Yes BRC1-RR1")
    assert_equal ProspectiveApplication::EXPERIENCE_NONE, ProspectiveApplicationImport.experience_for("Sometimes")
    assert_equal ProspectiveApplication::EXPERIENCE_NONE, ProspectiveApplicationImport.experience_for("")
  end

  test "recycled_handle? spots the Handle (YYYY) format" do
    assert ProspectiveApplicationImport.recycled_handle?("Sparkles (2019)")
    assert_not ProspectiveApplicationImport.recycled_handle?("Sparkles")
    assert_not ProspectiveApplicationImport.recycled_handle?("")
  end

  test "emergency_contact_from drops blank parts" do
    build = lambda do |name, relationship, phone|
      ProspectiveApplicationImport.emergency_contact_from(OpenStruct.new(
        "Emergency_Contact_Name__c" => name,
        "Emergency_Contact_Relationship__c" => relationship,
        "Emergency_Contact_Phone__c" => phone
      ))
    end

    assert_equal "Moon Beam (partner) phone 775-555-0199", build.call("Moon Beam", "partner", "775-555-0199")
    assert_equal "Moon Beam", build.call("Moon Beam", "", "")
    assert_equal "(partner) phone 775-555-0199", build.call("", "partner", "775-555-0199")
    assert_equal "", build.call("", "", "")
  end

  test "first_phone takes the first non-blank number" do
    ranger_info = OpenStruct.new("Phone" => "  ", "MobilePhone" => " 775-555-0142 ", "OtherPhone" => "775-555-0143")
    assert_equal "775-555-0142", ProspectiveApplicationImport.first_phone(ranger_info)
    assert_equal "", ProspectiveApplicationImport.first_phone(OpenStruct.new)
  end

  test "sanitize_street flattens embedded newlines" do
    assert_equal "1 Example St", ProspectiveApplicationImport.sanitize_street("1 Example\r\nSt\n")
  end

  test "blank mapped fields are stored as empty strings" do
    fake = fake_connector(
      [FakeSalesforceConnector.application_record("Known_Rangers_Names__c" => nil,
                                                  "Submit_Radio_Call_Signs__c" => nil)],
      [FakeSalesforceConnector.contact_record("a01SF001", "MailingState" => nil)]
    )

    row = run_import(fake, commit: false).new_applications.first
    assert_equal "", row.known_rangers
    assert_equal "", row.handles
    assert_equal "", row.state
  end

  private

  # A connector queued for one page: the application list, then the contact
  # batch. The fallback empty envelope ends pagination.
  def fake_connector(application_records, contact_records)
    FakeSalesforceConnector.new(query_results: [
      FakeSalesforceConnector.envelope(*application_records),
      FakeSalesforceConnector.envelope(*contact_records)
    ])
  end

  def run_import(fake, commit:)
    import = ProspectiveApplicationImport.new(connector: fake)
    import.import_unprocessed(commit: commit)
    import
  end
end
