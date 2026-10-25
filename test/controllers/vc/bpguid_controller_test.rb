# frozen_string_literal: true

require "test_helper"

# VC › BPGUID Lookup: the callsign lookup, the person card, the Salesforce
# Contacts search and the link a row's button makes. Nothing here may reach
# Salesforce: every search runs under a fake connector, and the tests that care
# assert what it was asked. A link is sent the way the row's button sends it:
# a PATCH carrying a signed link_token, minted here as the view mints it.
class Vc::BpguidControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include DomIdTestHelper
  include FakeSalesforceConnectorHelper

  GATE_MESSAGE = "Admin or Volunteer Coordinator role required to link Burner Profiles."
  RESULTS = "vc-bpguid-results"
  FIELDS = "FirstName,LastName,Email,Burner_Profile_Email__c,HomePhone,Phone,BPGUID__c,npe01__Home_Address__c"
  EMAIL = "testranger@example.com"
  ZERO_RESULTS = "Salesforce found no contacts for this search. Try the Burner Profile email the member sent, " \
                 "check the spelling, or end the name or email with * to match the start of it."
  # D16's three refusals, as the reader sees them.
  TOO_LONG = "That search is longer than 80 characters. Shorten it, then search again."
  SHORT_WILDCARD = "A search with * needs at least 3 other characters, as in smi*. " \
                   "Add more of the name or email, then search again."
  NO_OR = "Search for one name or email at a time. Remove OR, then search again."
  NOTICE = "vc-bpguid-notice"
  SUNNY_BPGUID = "b7e2a1c0-0001-4000-9001-000000009001"
  OUT_OF_DATE = "This result is out of date. Search again, then choose the contact."
  CONSEQUENCE = "A link takes effect at once for this person's shift sign-ups and tickets. " \
                "It can be replaced here, but only an Admin can remove it."
  LOOK_UP_FIRST = "To link one of these BPGUIDs, look up the person's callsign first, then search again."

  setup do
    Rails.cache.clear

    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    @event_manager = person(:retired_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    grant_role(@admin, Role::ADMIN)
    # VC and nothing else, so the role is proved on its own.
    grant_role(@vc, Role::VC)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    # After the role grants, so their audit rows do not stand in for the page's.
    ActionLog.delete_all
  end

  teardown do
    Rails.cache.clear
  end

  # The card's value for one label, as plain text; nil when the row is absent.
  def card_value(label)
    card_row(label)&.text&.squish
  end

  def card_row(label)
    css_select("dl.ui-label-value > dt").find { |dt| dt.text.squish == label }&.next_element
  end

  # Each printed line of the Address row.
  def address_lines
    card_row("Address").css("div").map { |line| line.text.squish }
  end

  def search_for(fake, text = EMAIL, holder: person(:active_ranger))
    with_fake_connector(fake) do
      post vc_bpguid_search_path(holder), params: { last_name_or_email: text }, as: :turbo_stream
    end
  end

  def statement(term) = "FIND {#{term}} RETURNING Contact (#{FIELDS})"

  def found(*records)
    FakeSalesforceConnector.search_envelope(*records)
  end

  def contact(overrides = {}) = FakeSalesforceConnector.contact_search_record(overrides)

  # What the live region was told, as text.
  def live_region_text
    css_select("turbo-stream[target=live-region] template").first.inner_html
  end

  def search_rows
    ActionLog.where(event: "salesforce-contact-search").order(:id).to_a
  end

  def token_for(holder, bpguid = SUNNY_BPGUID) = SalesforceContactSearch.link_token(holder, bpguid)

  # The PATCH a row's button sends.
  def link(holder, token = token_for(holder))
    patch vc_bpguid_person_path(holder), params: { link_token: token }, as: :turbo_stream
  end

  # The audit rows a link writes against the person.
  def link_rows(holder)
    ActionLog.where(event: "person-update", target_person_id: holder.id).order(:id).to_a
  end

  # The results' last cell, one per row: the button, the badge or nothing.
  def action_cells
    css_select("turbo-stream[target=#{RESULTS}] template tbody tr").map { |row| row.css("td").last }
  end

  def link_buttons
    css_select("turbo-stream[target=#{RESULTS}] template a[data-turbo-method=patch]")
  end

  # D8: a refusal answers 200 with one stream update into the notice slot.
  def assert_link_refused(sentence)
    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "turbo-stream", count: 1
    assert_select "turbo-stream[action=update][target=?] template", NOTICE do
      assert_select "[role=alert] h3", text: "BPGUID Not Linked"
      assert_select "[role=alert] p", text: sentence
    end
  end

  # ------------------------------------------------------------- the gate

  # C1
  test "an admin gets both forms, and opening the page asks Salesforce nothing" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@admin)

    with_fake_connector(fake) { get vc_bpguid_path }

    assert_response :success
    assert_select "h1", text: "BPGUID Lookup"
    assert_select "input[name=callsign][required][autofocus]"
    # The search form is here before anyone is looked up, empty and not focused.
    assert_select "[role=heading]", text: "Search Salesforce"
    assert_select "form[action=?][method=post] input[name=last_name_or_email]:not([value]):not([autofocus])",
                  vc_bpguid_search_path
    assert_no_match "Mock Data", response.body
    assert_empty fake.searches
    assert_empty fake.queries
    assert_unique_dom_ids
  end

  # C2
  test "a vc gets the lookup and a person's card on the role alone" do
    sign_in_as(@vc)

    get vc_bpguid_path
    assert_response :success

    get vc_bpguid_person_path(person(:active_ranger))
    assert_response :success
  end

  # C3
  test "event management and a person with no role are turned away from the lookup and the card" do
    [@event_manager, @outsider].each do |reader|
      sign_in_as(reader)

      get vc_bpguid_path
      assert_redirected_to me_root_path
      assert_equal GATE_MESSAGE, flash[:error]

      get vc_bpguid_person_path(person(:active_ranger))
      assert_redirected_to me_root_path
      assert_equal GATE_MESSAGE, flash[:error]

      sign_out
    end
  end

  # C4
  test "a signed-out reader is sent to sign in" do
    get vc_bpguid_path
    assert_redirected_to root_path

    get vc_bpguid_person_path(person(:active_ranger))
    assert_redirected_to root_path
  end

  # C3b
  test "event management and a person with no role are turned away before Salesforce is searched" do
    fake = FakeSalesforceConnector.new

    [@event_manager, @outsider].each do |reader|
      sign_in_as(reader)

      search_for(fake)
      assert_redirected_to me_root_path
      assert_equal GATE_MESSAGE, flash[:error]

      sign_out
    end

    assert_empty fake.searches
    assert_empty search_rows
  end

  # C4b
  test "a signed-out search is sent to sign in" do
    fake = FakeSalesforceConnector.new

    search_for(fake)

    assert_redirected_to root_path
    assert_empty fake.searches
  end

  # ------------------------------------------------------------- the lookup

  # C5
  test "a callsign in any case goes to that person" do
    sign_in_as(@vc)

    %w[TestRanger testranger].each do |callsign|
      get vc_bpguid_path(callsign:)

      assert_redirected_to vc_bpguid_person_path(person(:active_ranger))
    end
  end

  # C6
  test "a callsign typed with different spacing reaches the person through the normalized match" do
    sign_in_as(@vc)

    get vc_bpguid_path(callsign: "Test Ranger")

    assert_redirected_to vc_bpguid_person_path(person(:active_ranger))
  end

  # C7
  test "a callsign nobody has keeps the typed value and says so" do
    sign_in_as(@vc)

    get vc_bpguid_path(callsign: "Nobody")

    assert_response :success
    assert_equal "No account has the callsign Nobody. Check the spelling, then look it up again.", flash[:error]
    assert_select "input[name=callsign][value=Nobody]"
  end

  # C7: punctuation alone normalizes to "", which must match nobody rather than
  # whichever account has a blank normalized callsign.
  test "a callsign of punctuation alone matches nobody" do
    # No fixture has a blank normalized callsign, so give one an account to find.
    person(:inactive_ranger).update_column(:callsign_normalized, "")
    sign_in_as(@vc)

    get vc_bpguid_path(callsign: "!!!")

    assert_response :success
    assert_equal "No account has the callsign !!!. Check the spelling, then look it up again.", flash[:error]
  end

  # C5/C6: D12, normalized callsigns are not unique, so the exact one wins.
  test "the exact callsign wins over another account with the same normalized callsign" do
    person(:ranger_with_custom_gender).update_columns(callsign: "Test-Ranger", callsign_normalized: "testranger")
    sign_in_as(@vc)

    get vc_bpguid_path(callsign: "TestRanger")
    assert_redirected_to vc_bpguid_person_path(person(:active_ranger))

    get vc_bpguid_path(callsign: "Test-Ranger")
    assert_redirected_to vc_bpguid_person_path(person(:ranger_with_custom_gender))
  end

  # ------------------------------------------------------------- the card

  # C8
  test "the card lists every optional field a person has" do
    holder = person(:ranger_with_custom_gender)
    sign_in_as(@vc)

    get vc_bpguid_person_path(holder)

    assert_response :success
    assert_equal "Custom A Gender", card_value("Name")
    assert_equal "Cus", card_value("Preferred Name")
    assert_equal ["456 Oak Ave Apt 2B", "Suite 100", "Portland, Oregon 97201", "United States"], address_lines
    assert_equal PhoneFormatter.format("+17755550103"), card_value("Alt. Phone")
    assert_equal PhoneFormatter.format("+17755550102"), card_value("Home Phone")
    assert_equal "customgender@example.com", card_value("Email")
    assert_equal "CUSTOMGENDER-BPGUID-0002", card_value("BPGUID")
    assert_unique_dom_ids
  end

  # C8
  test "the card leaves out the optional fields a person does not have" do
    sign_in_as(@vc)

    get vc_bpguid_person_path(person(:active_ranger))

    assert_nil card_row("Alt. Phone")
    assert_equal "None stated", card_value("Preferred Name")
    assert_equal ["123 Main St", "San Francisco, California 94102", "United States"], address_lines
  end

  # C8: a blank street1 is legitimate for statuses that need only basic PII, so
  # the rest of the address must not hang off it.
  test "the address still shows the city and country without a street" do
    holder = person(:active_ranger)
    holder.update_columns(street1: "", apt: "")
    sign_in_as(@vc)

    get vc_bpguid_person_path(holder)

    assert_equal ["San Francisco, California 94102", "United States"], address_lines
  end

  # C8: COUNTRY_LABELS[""] is "Choose Country".
  test "an address with nothing on file reads none stated, never choose country" do
    holder = person(:active_ranger)
    holder.update_columns(street1: "", apt: "", street2: "", city: "", state: "", zip: "", country: "")
    sign_in_as(@vc)

    get vc_bpguid_person_path(holder)

    assert_equal "None stated", card_value("Address")
    assert_no_match "Choose Country", response.body
  end

  # C9: D13 (c), the state shows whichever way a country with states is stored.
  test "the state shows for a country with states, stored by name or by code" do
    holder = person(:active_ranger)
    sign_in_as(@vc)

    get vc_bpguid_person_path(holder)
    assert_includes card_value("Address"), "San Francisco, California"

    holder.update_column(:country, "US")
    get vc_bpguid_person_path(holder)
    assert_includes card_value("Address"), "San Francisco, California"
    assert_includes address_lines, "United States"
  end

  # C9
  test "the state is left out for a country without states, stored by name or by code" do
    holder = person(:active_ranger)
    sign_in_as(@vc)

    ["GB", "United Kingdom"].each do |country|
      holder.update_column(:country, country)
      get vc_bpguid_person_path(holder)

      assert_not_includes card_value("Address"), "California"
      assert_includes address_lines, "San Francisco 94102"
      assert_includes address_lines, "United Kingdom"
    end
  end

  # C10: D5
  test "a person without a BPGUID reads none on file" do
    sign_in_as(@vc)

    get vc_bpguid_person_path(person(:prospective_ranger))

    assert_response :success
    assert_equal "None on file", card_value("BPGUID")
    assert_equal "newbie@example.com", card_value("Email")
  end

  # C10
  test "an unknown person goes back to the lookup" do
    sign_in_as(@vc)

    get vc_bpguid_person_path(person_id: 0)

    assert_redirected_to vc_bpguid_path
    assert_equal "The person could not be found.", flash[:error]
  end

  # ------------------------------------------------------------- the search form

  # C10b
  test "the person page names the person over a search field holding their email" do
    holder = person(:prospective_ranger)
    sign_in_as(@vc)

    with_fake_connector(FakeSalesforceConnector.new) { get vc_bpguid_person_path(holder) }

    assert_response :success
    form_section = css_select("section").find do |section|
      section.at_css("[role=heading]")&.text&.squish == "Search Salesforce for ProspectiveNewbie"
    end
    assert form_section, "the search form sits under a heading naming the person"
    assert form_section.at_css("input[name=last_name_or_email][value='newbie@example.com'][required][maxlength='80'][autofocus]")
    # The lookup form stays, so another person is one callsign away.
    assert_select "form[action=?][method=get] input[name=callsign]:not([autofocus])", vc_bpguid_path
    assert_select "##{RESULTS}", text: "Search Salesforce to see the contacts that match."
    assert_unique_dom_ids
  end

  # C10b: under SF_MOCK_DATA the answers are canned, and the heading says so.
  test "the contacts heading says when the answers are canned" do
    sign_in_as(@vc)

    with_fake_connector(Salesforce::MockConnector.new) { get vc_bpguid_person_path(person(:active_ranger)) }
    assert_select "section .badge", text: "Mock Data"

    with_fake_connector(FakeSalesforceConnector.new) { get vc_bpguid_person_path(person(:active_ranger)) }
    assert_select "section .badge", text: "Mock Data", count: 0
  end

  # ------------------------------------------------------------- the search

  # C11
  test "a search answers 200 with stream updates for the results and the live region" do
    fake = FakeSalesforceConnector.new(query_results: [found(contact)])
    sign_in_as(@vc)

    search_for(fake)

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "turbo-stream[action=update][target=?]", RESULTS
    assert_select "turbo-stream[action=update][target=live-region]"
    assert_equal [statement(EMAIL)], fake.searches
    assert_equal "1 contact.", live_region_text
  end

  # C12
  test "the typed text reaches Salesforce escaped, with the wildcard kept" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@vc)

    search_for(fake, "first-last+bm@example.com")
    search_for(fake, "smi*")

    assert_equal [statement("first\\-last\\+bm@example.com"), statement("smi*")], fake.searches
  end

  # C13
  test "the contacts reach the page under the owner's column labels" do
    fake = FakeSalesforceConnector.new(query_results: [found(
      contact,
      contact("FirstName" => nil, "LastName" => "Stone", "Email" => nil, "Burner_Profile_Email__c" => nil,
              "HomePhone" => nil, "Phone" => nil, "BPGUID__c" => nil),
      contact("Burner_Profile_Email__c" => "SUNNY.DAY@example.com", "Phone" => "(775) 555-0101")
    )])
    sign_in_as(@vc)

    search_for(fake)

    assert_select "turbo-stream[target=?] template", RESULTS do |template|
      # The owner's seven fields in four columns, then the row action.
      assert_equal ["Contact", "Email", "Phone", "BPGUID", "Actions"], template.css("thead th").map { |th| th.text.squish }
      assert_select "tbody th[scope=row]", text: /\ASunny Day/
      first, stone, same = template.css("tbody tr").to_a
      assert_equal "Sunny Day 9001 Example St, Example City, NV 99999, United States",
                   first.at_css("th[scope=row]").text.squish
      # Every email address and phone number unlabelled; the BPGUID only as a badge saying there is one.
      assert_equal ["sunny.day@example.com sunny@example.net", "775-555-0101 775-555-0111",
                    "Present", "Use This BPGUID"],
                   first.css("td").map { |td| td.text.squish }
      assert_no_match SUNNY_BPGUID, first.css("td")[2].to_html
      # A contact with one name keeps it, and no email, phone or BPGUID says so.
      assert_match(/\AStone 9001/, stone.at_css("th[scope=row]").text.squish)
      assert_equal ["No email addresses", "No phone numbers", "None or Hidden"],
                   stone.css("td").first(3).map { |td| td.text.squish }
      assert stone.css("td")[2].at_css(".badge-error"), "no BPGUID is an error badge"
      # An address or number in both fields, in another case or format, is listed once.
      assert_equal ["sunny.day@example.com", "775-555-0101"],
                   same.css("td").first(2).map { |td| td.text.squish }
      assert_select "p", text: "3 contacts."
      # A person is shown, so the look-up-first hint is not.
      assert_no_match LOOK_UP_FIRST, template.text.squish
    end
  end

  # C14
  test "a value that looks like markup arrives as text" do
    fake = FakeSalesforceConnector.new(query_results: [found(contact("LastName" => "<script>alert(1)</script>"))])
    sign_in_as(@vc)

    search_for(fake)

    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_select "template script", count: 0
  end

  # C14: turbo_stream.update marks a plain String html_safe, so the controller
  # escapes the sentence. No real sentence holds markup; this one does.
  test "the live region gets its sentence as text" do
    original = SalesforceContactSearch.instance_method(:summary)
    SalesforceContactSearch.define_method(:summary) { "<b>x</b>" }
    sign_in_as(@vc)

    search_for(FakeSalesforceConnector.new)

    assert_select "turbo-stream[target=live-region] template b", count: 0
    assert_equal "&lt;b&gt;x&lt;/b&gt;", live_region_text
  ensure
    SalesforceContactSearch.define_method(:summary, original)
  end

  # C15
  test "a failed sign-in says so, sends no search, and points at the settings" do
    fake = FakeSalesforceConnector.new(auth_result: false)
    sign_in_as(@vc)

    search_for(fake)

    assert_empty fake.searches
    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "h3", text: "Could Not Sign In to Salesforce"
      assert_select "p", text: "No search was sent. Ask an Admin to check the Salesforce settings, then search again."
    end
    assert_equal "The search did not run.", live_region_text
  end

  # C16
  test "a search Salesforce refuses shows its reason and no table" do
    fake = FakeSalesforceConnector.new(query_results: [false])
    sign_in_as(@vc)

    search_for(fake)

    assert_response :success
    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "h3", text: "Salesforce Could Not Run the Search"
      assert_select "pre", text: "fake salesforce failure"
      assert_select "p", text: "Check the name or email, then search again."
      assert_select "table", count: 0
    end
    assert_equal "The search did not run.", live_region_text
  end

  # C16: the callout's title already says what the connector's prefix says.
  test "the reason drops the prefix the callout title already says" do
    fake = FakeSalesforceConnector.new(query_results: [false])
    fake.define_singleton_method(:error_message) { "Salesforce query failed: INVALID_FIELD: No such column" }
    sign_in_as(@vc)

    search_for(fake)

    assert_select "turbo-stream[target=?] template pre", RESULTS, text: "INVALID_FIELD: No such column"
  end

  # C17
  test "a search that finds nobody says what to try next, with no table" do
    sign_in_as(@vc)

    search_for(FakeSalesforceConnector.new)

    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "p", text: ZERO_RESULTS
      assert_select "table", count: 0
    end
    assert_equal ZERO_RESULTS, live_region_text
  end

  # C18: D11, Salesforce stops at 250 without saying so.
  test "a full answer of 250 contacts warns that there may be more" do
    sign_in_as(@vc)

    search_for(FakeSalesforceConnector.new(query_results: [found(*Array.new(250) { contact })]))
    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "[role=status]", text: /Salesforce stops at 250 contacts, so there may be more\./
      assert_select "tbody tr", count: 250
    end
    # The callout arrives already holding its words, so the live region says it.
    assert_equal "250 contacts. Salesforce stops at 250, so there may be more.", live_region_text

    search_for(FakeSalesforceConnector.new(query_results: [found(*Array.new(249) { contact })]))
    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "[role=status]", count: 0
    end
    assert_equal "249 contacts.", live_region_text
  end

  # C19
  test "the search keeps a refused statement out of the error log" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@vc)

    search_for(fake)

    assert_equal false, fake.log_rejections
  end

  # C20
  test "nothing about the search is kept in the request log" do
    Setting.find_or_initialize_by(name: Setting::REQUEST_LOG_ENABLED).update!(value: "true")
    holder = person(:active_ranger)
    sign_in_as(@vc)

    search_for(FakeSalesforceConnector.new(query_results: [found(contact)]), holder:)

    entry = RequestLog.order(:id).last
    assert_equal "vc/bpguid/#{holder.id}/search", entry.url, "the search was recorded, so the nils below mean something"
    assert_nil entry.request_payload
    assert_nil entry.response_payload
  end

  # C36: a search with no one shown runs, but no row can be linked.
  test "a search before any lookup shows the contacts with no Actions column and no buttons" do
    fake = FakeSalesforceConnector.new(query_results: [found(contact, contact("BPGUID__c" => nil))])
    sign_in_as(@vc)

    with_fake_connector(fake) do
      post vc_bpguid_search_path, params: { last_name_or_email: EMAIL }, as: :turbo_stream
    end

    assert_response :success
    assert_equal [statement(EMAIL)], fake.searches
    assert_select "turbo-stream[target=?] template", RESULTS do |template|
      assert_equal ["Contact", "Email", "Phone", "BPGUID"], template.css("thead th").map { |th| th.text.squish }
      assert_equal 2, template.css("tbody tr").size
      assert_equal 4, template.css("tbody tr").first.css("th, td").size
      assert_no_match CONSEQUENCE, template.text.squish
      assert_select "[role=note]", text: LOOK_UP_FIRST
    end
    assert_empty link_buttons
    assert_nil search_rows.sole.target_person_id
  end

  # C21: D9
  test "each search writes one action log row against the person, never the contacts" do
    holder = person(:active_ranger)
    sign_in_as(@vc)

    search_for(FakeSalesforceConnector.new(query_results: [found(contact)]), holder:)

    rows = search_rows
    assert_equal 1, rows.size
    assert_equal @vc.id, rows.first.person_id
    assert_equal holder.id, rows.first.target_person_id
    assert_equal({ "search" => EMAIL, "total" => 1 }, rows.first.data)
  end

  # C21
  test "a failed search's action log row carries the error" do
    sign_in_as(@vc)

    search_for(FakeSalesforceConnector.new(query_results: [false]))

    assert_equal [{ "search" => EMAIL, "error" => "fake salesforce failure" }], search_rows.map(&:data)
  end

  # C22: D10
  test "the Groundhog Day Server opens the person page but never searches" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@vc)

    ENV["RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"] = "2026-04-16 12:00:00"
    begin
      with_fake_connector(fake) { get vc_bpguid_person_path(person(:active_ranger)) }
      assert_response :success

      search_for(fake)
    ensure
      ENV.delete("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME")
    end

    assert_redirected_to me_root_path
    assert_match "Groundhog Day Server", flash[:error]
    assert_empty fake.searches
    assert_empty search_rows
  end

  # C23: D2
  test "a blank search is refused without asking Salesforce, and the field's name is filtered from logs" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@vc)

    search_for(fake, "  ")

    assert_response :bad_request
    assert_empty fake.searches

    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal "[FILTERED]", filter.filter("last_name_or_email" => "a@example.com")["last_name_or_email"]
  end

  # C32: D16 (a), the floor
  test "a search too broad to send is refused before Salesforce is asked" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@vc)

    {
      "s*" => SHORT_WILDCARD,
      "*" => SHORT_WILDCARD,
      "sm*" => SHORT_WILDCARD,
      "jo* OR ma*" => SHORT_WILDCARD,
      "jo* or ma*" => SHORT_WILDCARD,
      "smith OR jones" => NO_OR,
      "a" * 81 => TOO_LONG
    }.each do |text, sentence|
      ActionLog.delete_all
      search_for(fake, text)

      assert_response :success
      assert_select "turbo-stream[target=?] template", RESULTS do
        assert_select "h3", text: "Narrow the Search"
        assert_select "p", text: sentence
      end
      assert_equal "The search was not sent.", live_region_text
      assert_equal [{ "search" => text, "error" => sentence }], search_rows.map(&:data), text
    end

    assert_empty fake.searches
  end

  # C32: the floor runs before sign-in, and short plain words still go out.
  test "the floor is checked before signing in, and passes a short name or a leading wildcard" do
    sign_in_as(@vc)

    search_for(FakeSalesforceConnector.new(auth_result: false), "sm*")
    assert_select "turbo-stream[target=?] template h3", RESULTS, text: "Narrow the Search"
    assert_select "turbo-stream[target=?] template h3", RESULTS, text: "Could Not Sign In to Salesforce", count: 0

    fake = FakeSalesforceConnector.new
    search_for(fake, "Li")
    search_for(fake, "*tone")
    # Only a standalone OR is refused; the pre-filled email is often a .org one.
    search_for(fake, "jordan@example.org")

    assert_equal [statement("Li"), statement("*tone"), statement("jordan@example.org")], fake.searches
  end

  # ------------------------------------------------------------- the link

  # C3c
  test "event management and a person with no role are turned away before a link is written" do
    holder = person(:prospective_ranger)
    token = token_for(holder)

    [@event_manager, @outsider].each do |reader|
      sign_in_as(reader)

      link(holder, token)
      assert_redirected_to me_root_path
      assert_equal GATE_MESSAGE, flash[:error]

      sign_out
    end

    assert_nil holder.reload.bpguid
    assert_empty link_rows(holder)
  end

  # C24: D6
  test "a row gets a button only when its BPGUID is present and not the person's own" do
    holder = person(:active_ranger)
    fake = FakeSalesforceConnector.new(query_results: [found(
      contact("BPGUID__c" => nil),
      contact("BPGUID__c" => "testranger-bpguid-0001"),
      contact
    )])
    sign_in_as(@vc)

    search_for(fake, holder:)

    assert_select "turbo-stream[target=?] template thead th", RESULTS, count: 5 do |headings|
      assert_equal "Actions", headings.last.text.squish
    end
    blank, own, other = action_cells
    assert_empty blank.text.squish
    assert_nil blank.at_css("a")
    assert_equal "Linked", own.text.squish
    assert own.at_css(".badge"), "the person's own BPGUID, in another case, is marked Linked"
    assert_nil own.at_css("a")

    button = other.at_css("a[data-turbo-method=patch]")
    assert button, "any other BPGUID gets the button"
    assert_equal "Use This BPGUID", button.text.squish
    href = URI.parse(button["href"])
    assert_equal vc_bpguid_person_path(holder), href.path
    # The value travels only inside the signed token, never as a bpguid param.
    query = Rack::Utils.parse_query(href.query)
    assert_equal ["link_token"], query.keys
    assert_equal({ "person_id" => holder.id, "bpguid" => SUNNY_BPGUID, "was" => "TESTRANGER-BPGUID-0001" },
                 SalesforceContactSearch.verified_link(query["link_token"]))
    assert button["aria-label"].start_with?("Use This BPGUID")
  end

  # C24: label-in-name, and two contacts with one name still sound different.
  test "each button's accessible name names the contact and the BPGUID it writes" do
    other = "b7e2a1c0-0002-4000-9002-000000009002"
    fake = FakeSalesforceConnector.new(query_results: [found(
      contact,
      contact("BPGUID__c" => other),
      contact("FirstName" => nil, "LastName" => nil, "BPGUID__c" => "B-3")
    )])
    sign_in_as(@vc)

    search_for(fake, holder: person(:prospective_ranger))

    assert_equal ["Use This BPGUID — Sunny Day — #{SUNNY_BPGUID}", "Use This BPGUID — Sunny Day — #{other}",
                  "Use This BPGUID — B-3"], link_buttons.map { |button| button["aria-label"] }
  end

  # C25: D4 (a), a confirm only when the link replaces one.
  test "the button asks first only when it would replace the person's BPGUID" do
    sign_in_as(@vc)

    search_for(FakeSalesforceConnector.new(query_results: [found(contact)]), holder: person(:prospective_ranger))
    assert_nil link_buttons.first["data-turbo-confirm"], "a first link goes straight through"

    search_for(FakeSalesforceConnector.new(query_results: [found(
      contact,
      contact("FirstName" => nil, "LastName" => nil, "Email" => nil, "BPGUID__c" => "B-3")
    )]), holder: person(:active_ranger))
    named, nameless = link_buttons
    assert_equal "patch", named["data-turbo-method"]

    dialog = Nokogiri::HTML5.fragment(named["data-turbo-confirm"])
    assert_includes dialog.text.squish, "Replace BPGUID"
    assert_includes dialog.text.squish, "TestRanger's BPGUID is TESTRANGER-BPGUID-0001. " \
                                        "Replace it with #{SUNNY_BPGUID}, from Sunny Day, sunny.day@example.com?"
    confirm = dialog.at_css("#turbo-confirm-button")
    assert_equal "Replace BPGUID", confirm.text.squish
    assert_includes confirm["class"].split, "btn-error"

    # The "from" clause drops what is blank.
    assert_includes Nokogiri::HTML5.fragment(nameless["data-turbo-confirm"]).text.squish,
                    "TestRanger's BPGUID is TESTRANGER-BPGUID-0001. Replace it with B-3?"
  end

  # C26: D8, a 303 so fetch follows with a GET, not a second PATCH.
  test "a link writes the contact's BPGUID, audits it, and goes back to the person" do
    holder = person(:prospective_ranger)
    sign_in_as(@vc)

    link(holder)

    assert_response :see_other
    assert_redirected_to vc_bpguid_person_path(holder)
    assert_equal "ProspectiveNewbie's BPGUID is now #{SUNNY_BPGUID}.", flash[:success]
    assert_equal SUNNY_BPGUID, holder.reload.bpguid

    rows = link_rows(holder)
    assert_equal 1, rows.size
    assert_equal @vc.id, rows.first.person_id
    assert_equal "BPGUID linked on VC › BPGUID Lookup", rows.first.message
    assert_equal [nil, SUNNY_BPGUID], rows.first.data["bpguid"]
  end

  # C26: the page it goes back to shows the new link, with the results cleared.
  test "after a link the card shows the new BPGUID" do
    holder = person(:prospective_ranger)
    sign_in_as(@vc)

    link(holder)
    with_fake_connector(FakeSalesforceConnector.new) { follow_redirect! }

    assert_response :success
    assert_equal SUNNY_BPGUID, card_value("BPGUID")
    assert_select "##{RESULTS}", text: "Search Salesforce to see the contacts that match."
  end

  # C27: D3, refused whatever the case, since the collation ignores it.
  test "a BPGUID another account holds is refused in place, naming the holder" do
    holder = person(:prospective_ranger)
    sign_in_as(@vc)

    %w[TESTRANGER-BPGUID-0001 testranger-bpguid-0001].each do |bpguid|
      link(holder, token_for(holder, bpguid))

      assert_link_refused "#{bpguid} is already linked to TestRanger. " \
                          "Ask an Admin to check whether the two accounts are the same person."
      assert_includes response.body, "already linked to TestRanger"
      assert_nil flash[:error]
    end

    assert_nil holder.reload.bpguid
    assert_empty link_rows(holder)
  end

  # C28: D4, a replacement goes through once confirmed, and is audited old to new.
  test "a link replaces the BPGUID the person had when the row rendered" do
    holder = person(:ranger_with_custom_gender)
    sign_in_as(@vc)

    link(holder)

    assert_response :see_other
    assert_equal SUNNY_BPGUID, holder.reload.bpguid
    assert_equal [["CUSTOMGENDER-BPGUID-0002", SUNNY_BPGUID]], link_rows(holder).map { |row| row.data["bpguid"] }
  end

  # C29: update_attribute, so a record failing an unrelated check still links
  # and keeps its legacy phone as stored.
  test "a link skips validation and leaves the phones as stored" do
    holder = person(:active_ranger)
    holder.update_columns(street1: "", home_phone: "7755550101")
    sign_in_as(@vc)

    link(holder.reload)

    assert_response :see_other
    holder.reload
    assert_equal SUNNY_BPGUID, holder.bpguid
    assert_equal "7755550101", holder.home_phone
  end

  # C30
  test "a BPGUID longer than the column holds is refused, and a link with no token is a bad request" do
    holder = person(:prospective_ranger)
    sign_in_as(@vc)

    link(holder, token_for(holder, "B" * 65))
    assert_link_refused "That BPGUID is longer than the 64 characters the Clubhouse can store."
    assert_nil holder.reload.bpguid

    patch vc_bpguid_person_path(holder), as: :turbo_stream
    assert_response :bad_request
    assert_nil holder.reload.bpguid
    assert_empty link_rows(holder)
  end

  # C31
  test "the person page and a results stream share no DOM id" do
    holder = person(:active_ranger)
    sign_in_as(@vc)

    with_fake_connector(FakeSalesforceConnector.new) { get vc_bpguid_person_path(holder) }
    assert_unique_dom_ids
    page_ids = css_select("[id]").map { |element| element["id"] } -
               css_select("##{RESULTS} [id]").map { |element| element["id"] }

    search_for(FakeSalesforceConnector.new(query_results: [found(
      contact("BPGUID__c" => nil), contact("BPGUID__c" => "TESTRANGER-BPGUID-0001"), contact
    )]), holder:)
    assert_select "turbo-stream[target=?] template tbody tr", RESULTS, count: 3
    assert_unique_dom_ids
    stream_ids = css_select("turbo-stream[target=#{RESULTS}] template [id]").map { |element| element["id"] }
    assert_empty page_ids & stream_ids
  end

  # C33: the signed link is the only way a BPGUID reaches update.
  test "a typed bpguid without a link token is a bad request and writes nothing" do
    holder = person(:prospective_ranger)
    sign_in_as(@vc)

    patch vc_bpguid_person_path(holder), params: { bpguid: SUNNY_BPGUID }, as: :turbo_stream

    assert_response :bad_request
    assert_nil holder.reload.bpguid
    assert_empty link_rows(holder)
  end

  # C33
  test "an altered, borrowed or expired link token is refused as out of date" do
    holder = person(:prospective_ranger)
    sign_in_as(@vc)

    altered = token_for(holder)
    altered[-1] = altered[-1] == "0" ? "1" : "0"
    link(holder, altered)
    assert_link_refused OUT_OF_DATE

    # Minted for another person's row, sent to this person's path.
    link(holder, token_for(person(:active_ranger)))
    assert_link_refused OUT_OF_DATE

    expired = token_for(holder)
    travel(SalesforceContactSearch::LINK_LIFETIME + 1.minute) { link(holder, expired) }
    assert_link_refused OUT_OF_DATE

    assert_nil holder.reload.bpguid
    assert_empty link_rows(holder)

    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal "[FILTERED]", filter.filter("link_token" => "x")["link_token"]
  end

  # C34: D8, a row rendered before another tab or VC linked the person.
  test "a link from a row rendered before the BPGUID changed is refused" do
    holder = person(:prospective_ranger)
    token = token_for(holder)
    holder.update_column(:bpguid, "OTHER-0001")
    sign_in_as(@vc)

    link(holder, token)

    assert_link_refused "ProspectiveNewbie's BPGUID changed since this search (it is now OTHER-0001). " \
                        "Search again before linking."
    assert_equal "OTHER-0001", holder.reload.bpguid
    assert_empty link_rows(holder)
  end

  # C34: the same when the link was cleared in between.
  test "a link from a row rendered before the BPGUID was cleared is refused" do
    holder = person(:active_ranger)
    token = token_for(holder)
    holder.update_column(:bpguid, nil)
    sign_in_as(@vc)

    link(holder, token)

    assert_link_refused "TestRanger's BPGUID changed since this search (it was cleared). Search again before linking."
    assert_nil holder.reload.bpguid
  end

  # C35: D4, the consequence sits beside the buttons, and only when there is one.
  test "results with a button say what a link does, and results without one do not" do
    holder = person(:active_ranger)
    sign_in_as(@vc)

    search_for(FakeSalesforceConnector.new(query_results: [found(contact("BPGUID__c" => nil), contact)]), holder:)
    assert_select "turbo-stream[target=?] template [role=note]", RESULTS, text: CONSEQUENCE

    search_for(FakeSalesforceConnector.new(query_results: [found(
      contact("BPGUID__c" => nil), contact("BPGUID__c" => "TESTRANGER-BPGUID-0001")
    )]), holder:)
    assert_select "turbo-stream[target=?] template [role=note]", RESULTS, count: 0
    assert_select "turbo-stream[target=?] template tbody tr", RESULTS, count: 2
  end

  # C20: a link, its 303 and a refusal keep nothing in the request log either.
  test "nothing about a link is kept in the request log" do
    Setting.find_or_initialize_by(name: Setting::REQUEST_LOG_ENABLED).update!(value: "true")
    holder = person(:prospective_ranger)
    sign_in_as(@vc)

    link(holder, token_for(holder, "TESTRANGER-BPGUID-0001"))
    assert_response :success
    link(holder)
    assert_response :see_other

    entries = RequestLog.where(url: "vc/bpguid/#{holder.id}").order(:id).to_a
    assert_equal [200, 303], entries.map(&:status), "both were recorded, so the nils below mean something"
    entries.each do |entry|
      assert_nil entry.request_payload
      assert_nil entry.response_payload
    end
  end
end
