# frozen_string_literal: true

require "test_helper"
require "ostruct"

# Envelopes are built the way Salesforce sends them -- every record and parent
# relationship carries an "attributes" key -- and decoded into OpenStructs, as
# Salesforce#soql_query hands them over. Neither the mock nor the fake adds
# "attributes" on its own.
class SalesforceQueryTest < ActiveSupport::TestCase
  include ErrorLogTestHelper

  SOQL = "SELECT Id FROM Ranger__c"

  setup do
    Current.reset
    Current.person = person(:echelon_ranger)
    ActionLog.delete_all
  end

  teardown do
    Current.reset
  end

  # ------------------------------------------------------------- flattening

  test "drops attributes from records, relationships and aggregate rows" do
    query = run_with(envelope(record("Id" => "a01", "Ranger_Info__r" => record({ "MailingCity" => "Example City" }, "Contact"))))
    assert_equal ["Id", "Ranger_Info__r.MailingCity"], query.columns
    assert_equal [["a01", "Example City"]], query.rows

    query = run_with(envelope(record({ "VC_Status__c" => "Not Yet Started", "expr0" => 4 }, "AggregateResult")))
    assert_equal ["VC_Status__c", "expr0"], query.columns
  end

  test "a relationship that is null first keeps the place the SELECT gave it" do
    query = run_with(envelope(
      record("Id" => "a01", "Ranger_Info__r" => nil, "Name" => "R-9001"),
      record("Id" => "a02", "Ranger_Info__r" => record({ "MailingCity" => "Example City" }, "Contact"), "Name" => "R-9002")
    ))

    assert_equal ["Id", "Ranger_Info__r.MailingCity", "Name"], query.columns
    assert_equal [["a01", nil, "R-9001"], ["a02", "Example City", "R-9002"]], query.rows
  end

  test "flattens two levels deep and compound fields" do
    contact = record({ "Owner" => record({ "Name" => "Sunny Day" }, "User"),
                       "MailingAddress" => { "city" => "Example City", "state" => "NV" } }, "Contact")
    query = run_with(envelope(record("Id" => "a01", "Ranger_Info__r" => contact)))

    assert_equal ["Id", "Ranger_Info__r.Owner.Name", "Ranger_Info__r.MailingAddress.city",
                  "Ranger_Info__r.MailingAddress.state"], query.columns
    assert_equal [["a01", "Sunny Day", "Example City", "NV"]], query.rows
  end

  test "a child subquery becomes its record count, and a null one stays nil" do
    notes = { "totalSize" => 2, "done" => true,
              "records" => [record({ "Body__c" => "one" }, "Note__c"), record({ "Body__c" => "two" }, "Note__c")] }
    query = run_with(envelope(record("Id" => "a01", "Notes__r" => notes), record("Id" => "a02", "Notes__r" => nil)))

    assert_equal ["Id", "Notes__r"], query.columns
    assert_equal SalesforceQuery::Children.new(total: 2), query.rows.first.last
    assert_nil query.rows.last.last
  end

  test "aggregate rows keep their nil group values" do
    query = run_with(envelope(
      record({ "VC_Status__c" => "Not Yet Started", "expr0" => 4 }, "AggregateResult"),
      record({ "VC_Status__c" => nil, "expr0" => 9 }, "AggregateResult")
    ))

    assert_equal [["Not Yet Started", 4], [nil, 9]], query.rows
  end

  test "SELECT COUNT() has no columns and no rows, and the count in total" do
    query = run_with(envelope(total: 42))

    assert_equal [], query.columns
    assert_equal [], query.rows
    assert_equal 42, query.total
  end

  test "a column is numeric only when every value it holds is a number or a child count" do
    notes = { "totalSize" => 1, "done" => true, "records" => [record({ "Body__c" => "one" }, "Note__c")] }
    query = run_with(envelope(
      record("Score__c" => 3, "Notes__r" => notes, "Mixed__c" => 1, "Blank__c" => nil, "Flag__c" => true),
      record("Score__c" => 1.5, "Notes__r" => nil, "Mixed__c" => "one", "Blank__c" => nil, "Flag__c" => false)
    ))

    assert_equal [true, true, false, false, false], query.columns.each_index.map { |index| query.numeric?(index) }
  end

  test "fields named like OpenStruct's own methods come through as columns" do
    query = run_with(envelope(record({ "to_h" => 1, "each_pair" => 2, "hash" => 3 }, "AggregateResult")))

    assert_equal ["to_h", "each_pair", "hash"], query.columns
    assert_equal [[1, 2, 3]], query.rows
  end

  # ------------------------------------------------------------- SOSL

  test "a statement opening with FIND is sent to the search, anything else to the query" do
    fake = FakeSalesforceConnector.new
    SalesforceQuery.new("  find {Sunny} RETURNING Contact(Id)", connector: fake).run
    SalesforceQuery.new(SOQL, connector: fake).run

    assert_equal ["  find {Sunny} RETURNING Contact(Id)"], fake.searches
    assert_equal [SOQL], fake.queries
    assert_equal false, fake.log_rejections
  end

  test "a search leads with each record's object type, over the union of every type's fields" do
    found = FakeSalesforceConnector.search_envelope(
      record({ "Id" => "003A", "LastName" => "Day" }, "Contact"),
      record({ "Id" => "a01A", "Name" => "R-9001" })
    )
    query = SalesforceQuery.new("FIND {Day}", connector: FakeSalesforceConnector.new(query_results: [found])).run

    assert_equal ["attributes.type", "Id", "LastName", "Name"], query.columns
    assert_equal [["Contact", "003A", "Day", nil], ["Ranger__c", "a01A", nil, "R-9001"]], query.rows
    assert_equal 2, query.total
    assert_not query.truncated?
  end

  test "a search that finds nothing has no columns and a total of zero" do
    query = SalesforceQuery.new("FIND {Nobody}", connector: FakeSalesforceConnector.new).run

    assert_equal [], query.columns
    assert_equal 0, query.total
    assert_nil query.error
  end

  test "only done false marks the answer as cut short" do
    assert run_with(envelope(record("Id" => "a01"), total: 2500, done: false)).truncated?
    assert_not run_with(envelope(record("Id" => "a01"), done: true)).truncated?
    assert_not run_with(envelope(record("Id" => "a01"))).truncated?
  end

  # ------------------------------------------------------------- failures

  test "a failed sign-in sends no query" do
    fake = FakeSalesforceConnector.new(auth_result: false)
    query = SalesforceQuery.new(SOQL, connector: fake).run

    assert_not query.signed_in?
    assert_equal "fake salesforce failure", query.error
    assert_empty fake.queries
  end

  test "a refused query leaves the sign-in standing and the reason in error" do
    query = run_with(false)

    assert query.signed_in?
    assert_equal "fake salesforce failure", query.error
  end

  test "the query is sent with refused queries kept out of the error log" do
    fake = FakeSalesforceConnector.new
    SalesforceQuery.new(SOQL, connector: fake).run

    assert_equal [SOQL], fake.queries
    assert_equal false, fake.log_rejections
  end

  test "an exception the connector does not soften is logged and reported, not raised" do
    fake = FakeSalesforceConnector.new
    fake.define_singleton_method(:soql_query) { |*, **| raise Net::HTTPBadResponse, "wrong status line" }

    silence_error_log do |calls|
      query = SalesforceQuery.new(SOQL, connector: fake).run

      assert_equal "Salesforce query failed: Net::HTTPBadResponse", query.error
      assert_equal [[:record_exception, "salesforce-query-exception"]], calls.map { |call| [call[:method], call[:args][1]] }
    end
    assert_equal 1, ActionLog.where(event: "salesforce-query").count
  end

  # ------------------------------------------------------------- the audit row

  test "each run leaves one action log row: the query and its total, or the query and its error" do
    run_with(envelope(record("Id" => "a01")))
    run_with(false)

    rows = ActionLog.where(event: "salesforce-query").order(:id).map(&:data)
    assert_equal [{ "soql" => SOQL, "total" => 1 }, { "soql" => SOQL, "error" => "fake salesforce failure" }], rows
  end

  private

  def run_with(result)
    SalesforceQuery.new(SOQL, connector: FakeSalesforceConnector.new(query_results: [result])).run
  end

  def record(fields, type = "Ranger__c")
    { "attributes" => { "type" => type, "url" => "/services/data/v57.0/sobjects/#{type}/x" } }.merge(fields)
  end

  def envelope(*records, total: records.size, done: nil)
    body = { "totalSize" => total, "records" => records }
    body["done"] = done unless done.nil?
    JSON.parse(body.to_json, object_class: OpenStruct)
  end
end
