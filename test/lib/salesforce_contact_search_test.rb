# frozen_string_literal: true

require "test_helper"
require "ostruct"

# One search on VC › BPGUID Lookup, with the fake connector passed in: no HTTP,
# no request.
class SalesforceContactSearchTest < ActiveSupport::TestCase
  include ErrorLogTestHelper

  EMAIL = "testranger@example.com"
  STATEMENT = "FIND {testranger@example.com} RETURNING Contact " \
              "(FirstName,LastName,Email,Burner_Profile_Email__c,HomePhone,Phone,BPGUID__c,npe01__Home_Address__c)"

  setup do
    Current.reset
    Current.person = person(:echelon_ranger)
    @person = person(:active_ranger)
    ActionLog.delete_all
  end

  teardown do
    Current.reset
  end

  # L1
  test "the statement is the owner's, over the typed text" do
    assert_equal STATEMENT, search(EMAIL).statement
  end

  # L2
  test "each record becomes a contact with a joined name and a trimmed bpguid" do
    found = run_with(envelope(
      record,
      record("FirstName" => nil, "LastName" => "Day", "BPGUID__c" => "  b-1  "),
      record("FirstName" => nil, "LastName" => nil, "BPGUID__c" => " "),
      { "attributes" => { "type" => "Contact" }, "LastName" => "Stone" }
    ))

    first, one_name, no_name, sparse = found.contacts
    assert_equal SalesforceContactSearch::Contact.new(
      name: "Sunny Day", email: "sunny.day@example.com", burner_profile_email: "sunny@example.net",
      home_phone: "775-555-0101", phone: "775-555-0111", bpguid: "b7e2a1c0-0001-4000-9001-000000009001",
      home_address: "9001 Example St, Example City, NV 99999, United States"
    ), first
    assert_equal "Day", one_name.name
    assert_equal "b-1", one_name.bpguid
    assert_equal "", no_name.name
    assert_nil no_name.bpguid
    # A field missing from the record reads nil.
    assert_equal "Stone", sparse.name
    assert_nil sparse.email
    assert_nil sparse.bpguid
  end

  # L3
  test "a failed sign-in sends no search" do
    fake = FakeSalesforceConnector.new(auth_result: false)
    found = search(EMAIL, fake).run

    assert_not found.signed_in?
    assert_equal "fake salesforce failure", found.error
    assert_empty fake.searches
  end

  # L4
  test "a refused search leaves the sign-in standing and the reason in error" do
    found = run_with(false)

    assert found.signed_in?
    assert_equal "fake salesforce failure", found.error
    assert_empty found.contacts
  end

  # L4: as the sibling page ruled, a 400 is shown to the reader, not logged.
  test "the search is sent with refused statements kept out of the error log" do
    fake = FakeSalesforceConnector.new
    search(EMAIL, fake).run

    assert_equal [STATEMENT], fake.searches
    assert_equal false, fake.log_rejections
  end

  # L5
  test "an exception the connector does not soften is logged and reported, not raised" do
    fake = FakeSalesforceConnector.new
    fake.define_singleton_method(:sosl_search) { |*, **| raise Net::HTTPBadResponse, "wrong status line" }

    silence_error_log do |calls|
      found = search(EMAIL, fake).run

      assert_equal "Salesforce query failed: Net::HTTPBadResponse", found.error
      assert_equal [[:record_exception, "salesforce-query-exception"]], calls.map { |call| [call[:method], call[:args][1]] }
      assert_equal({ query: STATEMENT }, calls.first[:kwargs][:extra])
    end
    assert_equal 1, ActionLog.where(event: "salesforce-contact-search").count
  end

  # L6: D9
  test "each run leaves one action log row against the person: the search and its total, or its error" do
    run_with(envelope(record))
    run_with(false)

    rows = ActionLog.where(event: "salesforce-contact-search").order(:id).to_a
    assert_equal [{ "search" => EMAIL, "total" => 1 }, { "search" => EMAIL, "error" => "fake salesforce failure" }],
                 rows.map(&:data)
    assert_equal [@person.id] * 2, rows.map(&:target_person_id)
    assert_equal [Current.person.id] * 2, rows.map(&:person_id)
  end

  # L7: D11
  test "a full answer of 250 contacts is capped, and 249 is not" do
    assert run_with(envelope(*Array.new(250) { record })).capped?
    assert_not run_with(envelope(*Array.new(249) { record })).capped?
  end

  # L8
  test "the summary says what happened in one sentence" do
    assert_equal "The search was not sent.", search("s*").run.summary
    assert_equal "The search did not run.", run_with(false).summary
    assert_equal "1 contact.", run_with(envelope(record)).summary
    assert_equal "2 contacts.", run_with(envelope(record, record)).summary
    # D11: the live region reads this, so the cap is in it.
    assert_equal "250 contacts. Salesforce stops at 250, so there may be more.",
                 run_with(envelope(*Array.new(250) { record })).summary
    assert_match(/\ASalesforce found no contacts for this search\. Try the Burner Profile email the member sent/,
                 run_with(envelope).summary)
  end

  # L13: D16 (a)
  test "the floor passes a narrow search and refuses a broad one" do
    # "or" inside a word is not the operator: a .org email, Moore, Taylor.
    ["smi*", "Li", "*tone", "sunny.d*", EMAIL, "smith AND jones", "Moore", "jordan@example.org", "taylor*"].each do |text|
      assert_nil search(text).refusal, text
    end

    wildcard = "A search with * needs at least 3 other characters, as in smi*. " \
               "Add more of the name or email, then search again."
    or_operator = "Search for one name or email at a time. Remove OR, then search again."
    {
      "s*" => wildcard,
      "**" => wildcard,
      "sm*" => wildcard,
      "smith OR jones" => or_operator,
      "smith or jones" => or_operator,
      "a" * 81 => "That search is longer than 80 characters. Shorten it, then search again."
    }.each do |text, sentence|
      assert_equal sentence, search(text).refusal, text
    end
  end

  # L13: a refused text never signs in, and still leaves its row.
  test "a refused search signs in to nothing and writes one action log row" do
    fake = FakeSalesforceConnector.new
    found = search("sm*", fake).run

    assert found.refused?
    assert_not found.signed_in?
    assert_empty fake.searches
    assert_equal 1, ActionLog.where(event: "salesforce-contact-search").count
  end

  # L14: D8, the signed row link.
  test "a link token reads back as the person, the BPGUID and the person's BPGUID when it was minted" do
    token = SalesforceContactSearch.link_token(@person, "B-1")

    assert_equal({ "person_id" => @person.id, "bpguid" => "B-1", "was" => "TESTRANGER-BPGUID-0001" },
                 SalesforceContactSearch.verified_link(token))
    assert_equal({ "person_id" => person(:prospective_ranger).id, "bpguid" => "B-1", "was" => "" },
                 SalesforceContactSearch.verified_link(SalesforceContactSearch.link_token(person(:prospective_ranger), "B-1")))
  end

  # L14: verified answers nil, never raises, for anything but a fresh token of its own.
  test "an altered, malformed, misdirected or expired link token reads back as nil" do
    token = SalesforceContactSearch.link_token(@person, "B-1")
    payload = { "person_id" => @person.id, "bpguid" => "B-1", "was" => "TESTRANGER-BPGUID-0001" }
    altered = token.dup
    altered[-1] = altered[-1] == "0" ? "1" : "0"

    assert_nil SalesforceContactSearch.verified_link(altered)
    assert_nil SalesforceContactSearch.verified_link("garbage")
    assert_nil SalesforceContactSearch.verified_link(
      SalesforceContactSearch.link_verifier.generate(payload, purpose: :other)
    )
    assert_nil SalesforceContactSearch.verified_link(
      Rails.application.message_verifier("another-verifier").generate(payload, purpose: SalesforceContactSearch::LINK_PURPOSE)
    )

    travel(SalesforceContactSearch::LINK_LIFETIME + 1.minute) do
      assert_nil SalesforceContactSearch.verified_link(token)
    end
  end

  # L15: D6
  test "a contact is linked when it holds the person's BPGUID in any case, and linkable when it holds another" do
    found = search(EMAIL)

    assert_not found.linked?(contact(nil))
    assert_not found.linkable?(contact(nil))
    assert found.linked?(contact("testranger-bpguid-0001"))
    assert_not found.linkable?(contact("testranger-bpguid-0001"))
    assert found.linkable?(contact("B-1"))
    assert_not found.linked?(contact("B-1"))

    newbie = SalesforceContactSearch.new(EMAIL, person: person(:prospective_ranger), connector: FakeSalesforceConnector.new)
    assert newbie.linkable?(contact("B-1"))
    assert newbie.linkable?(contact("testranger-bpguid-0001"))
    assert_not newbie.linked?(contact("B-1"))
    assert_not newbie.linkable?(contact(nil))

    # No one shown: nothing is linked, and nothing can be.
    nobody = SalesforceContactSearch.new(EMAIL, connector: FakeSalesforceConnector.new)
    assert_not nobody.linked?(contact("testranger-bpguid-0001"))
    assert_not nobody.linkable?(contact("B-1"))
  end

  private

  def search(text, connector = FakeSalesforceConnector.new)
    SalesforceContactSearch.new(text, person: @person, connector:)
  end

  def run_with(result)
    search(EMAIL, FakeSalesforceConnector.new(query_results: [result])).run
  end

  def record(overrides = {}) = FakeSalesforceConnector.contact_search_record(overrides)

  def envelope(*records) = FakeSalesforceConnector.search_envelope(*records)

  # A contact with only the BPGUID that linked? and linkable? read.
  def contact(bpguid)
    SalesforceContactSearch::Contact.new(name: "Sunny Day", email: nil, burner_profile_email: nil, home_phone: nil,
                                         phone: nil, bpguid:, home_address: nil)
  end
end
