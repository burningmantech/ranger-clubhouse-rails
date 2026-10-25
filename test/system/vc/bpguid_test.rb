# frozen_string_literal: true

require "application_system_test_case"

# VC › BPGUID Lookup in a browser: the search answers with turbo streams, and
# only a browser shows where focus lands after one. Dev verification must never
# press a row's button, so these are also the only proof that the Turbo method
# link, the confirm dialog, the 303 and the refusal stream work together. The
# fake connector swap is process-wide, so it reaches the server thread.
class Vc::BpguidTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include FakeSalesforceConnectorHelper

  RESULTS = "#vc-bpguid-results"
  SUNNY_BPGUID = "b7e2a1c0-0001-4000-9001-000000009001"

  setup do
    vc = person(:echelon_ranger)
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(vc, Role::VC)
    sign_in(vc)
  end

  def answering(*records)
    FakeSalesforceConnector.new(
      query_results: [FakeSalesforceConnector.search_envelope(*records)]
    )
  end

  def sunny(overrides = {}) = FakeSalesforceConnector.contact_search_record(overrides)

  # S1: D4 (a), a first link goes straight through.
  test "a vc looks a person up, searches, and links a contact's BPGUID" do
    holder = person(:prospective_ranger)

    with_fake_connector(answering(sunny)) do
      visit vc_bpguid_path
      fill_in "Callsign", with: "ProspectiveNewbie"
      click_on "Look Up Callsign"
      assert_field "Name, Email, or Phone", with: "newbie@example.com"

      click_on "Search Salesforce"
      assert_selector "#{RESULTS} th[scope=row]", text: "Sunny Day"
      assert_selector "#{RESULTS} [role=note]", text: "A link takes effect at once"

      click_on "Use This BPGUID"
      assert_text "ProspectiveNewbie's BPGUID is now #{SUNNY_BPGUID}."
      assert_no_selector "dialog[open]"
      assert_current_path vc_bpguid_person_path(holder)
      assert_selector "dl.ui-label-value dd", text: SUNNY_BPGUID
      # D8: the results are cleared once the link is made.
      assert_selector RESULTS, text: "Search Salesforce to see the contacts that match."
    end

    assert_equal SUNNY_BPGUID, holder.reload.bpguid
  end

  # S2: D4 (a), a replacement asks first, and Cancel means no.
  test "replacing a BPGUID asks first, and only Replace BPGUID replaces it" do
    holder = person(:active_ranger)

    with_fake_connector(answering(sunny)) do
      visit vc_bpguid_person_path(holder)
      click_on "Search Salesforce"
      assert_selector "#{RESULTS} th[scope=row]", text: "Sunny Day"

      click_on "Use This BPGUID"
      within "dialog[open]" do
        assert_text "Replace BPGUID"
        assert_text "TestRanger's BPGUID is TESTRANGER-BPGUID-0001."
        assert_text "sunny.day@example.com"
        find("#turbo-cancel-button").click
      end
      assert_no_selector "dialog[open]"
      assert_selector "dl.ui-label-value dd", text: "TESTRANGER-BPGUID-0001"
      assert_equal "TESTRANGER-BPGUID-0001", holder.reload.bpguid

      click_on "Use This BPGUID"
      assert_selector "dialog[open]", text: "Replace BPGUID"
      accept_confirm_dialog
      assert_text "TestRanger's BPGUID is now #{SUNNY_BPGUID}."
      assert_selector "dl.ui-label-value dd", text: SUNNY_BPGUID
    end

    assert_equal SUNNY_BPGUID, holder.reload.bpguid
  end

  # S3: D3 and D8, a refusal answers in place and the table stays. The held
  # BPGUID is on the last of 30 rows, far below the notice slot above the table.
  test "a BPGUID another account holds is refused above the table, which stays" do
    holder = person(:prospective_ranger)
    others = Array.new(29) { |i| sunny("LastName" => "Day #{i + 1}", "BPGUID__c" => "B-#{i + 1}") }
    held = sunny("FirstName" => "River", "LastName" => "Stone", "BPGUID__c" => "TESTRANGER-BPGUID-0001")

    with_fake_connector(answering(*others, held)) do
      visit vc_bpguid_person_path(holder)
      click_on "Search Salesforce"
      assert_selector "#{RESULTS} th[scope=row]", text: "River Stone"

      find("#{RESULTS} a[aria-label$='TESTRANGER-BPGUID-0001']").click
      assert_selector "#vc-bpguid-notice [role=alert]", text: "BPGUID Not Linked"
      # Brought into view, not left above the viewport with nothing visible changed.
      assert_selector "#vc-bpguid-notice [role=alert]", obscured: false
      assert_selector "#vc-bpguid-notice", text: "TESTRANGER-BPGUID-0001 is already linked to TestRanger."
      assert_selector "#{RESULTS} th[scope=row]", text: "River Stone"
      assert_current_path vc_bpguid_person_path(holder)
      assert_selector "dl.ui-label-value dd", text: "None on file"
    end

    assert_nil holder.reload.bpguid
  end

  # S4: D17 (b). Turbo disables the submitter while a search runs, which drops
  # a pressed button's focus to the page; Enter in the field keeps it there.
  test "a search started with Enter in the field leaves focus in the field" do
    fake = FakeSalesforceConnector.new(
      query_results: [FakeSalesforceConnector.search_envelope(FakeSalesforceConnector.contact_search_record)]
    )

    with_fake_connector(fake) do
      visit vc_bpguid_person_path(person(:prospective_ranger))
      assert_field "Name, Email, or Phone", with: "newbie@example.com"

      fill_in "Name, Email, or Phone", with: "sunny.day@example.com"
      find_field("Name, Email, or Phone").send_keys(:enter)

      assert_selector "#{RESULTS} p", text: "1 contact."
      assert_selector "#{RESULTS} th[scope=row]", text: "Sunny Day"
      assert_equal "last_name_or_email", page.evaluate_script("document.activeElement.name")
    end

    assert_equal ["FIND {sunny.day@example.com} RETURNING Contact " \
                  "(FirstName,LastName,Email,Burner_Profile_Email__c,HomePhone,Phone,BPGUID__c,npe01__Home_Address__c)"],
                 fake.searches
  end
end
