# frozen_string_literal: true

require "test_helper"

class Admin::SalesforceQueryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include DomIdTestHelper
  include FakeSalesforceConnectorHelper

  SOQL = "SELECT Id, Name FROM Ranger__c LIMIT 10"
  RESULTS = "salesforce-query-results"

  setup do
    Rails.cache.clear

    @tech_ninja = person(:echelon_ranger)
    @admin = person(:auditor_ranger)
    @outsider = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")

    grant_role(@admin, Role::ADMIN)
    # Tech Ninja and nothing else: the Admin role does not open this page, so
    # the tests have to prove the role on its own works.
    grant_role(@tech_ninja, Role::TECH_NINJA)

    # After the role grants, so their audit entries do not stand in for a run.
    ActionLog.delete_all
  end

  teardown do
    Rails.cache.clear
  end

  # ------------------------------------------------------------- the gate

  test "a tech ninja gets the page, and opening it asks Salesforce nothing" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@tech_ninja)

    with_fake_connector(fake) { get admin_salesforce_query_path }

    assert_response :success
    assert_select "h1", text: /Salesforce Query/
    assert_select "textarea[name=soql][required]"
    assert_select "##{RESULTS} .empty-state", text: /Run a query/
    assert_empty fake.queries
    assert_unique_dom_ids
  end

  test "an admin who is not a tech ninja is turned away before Salesforce is asked" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@admin)

    with_fake_connector(fake) do
      get admin_salesforce_query_path
      assert_redirected_to me_root_path
      assert_equal "Tech Ninja role required to query Salesforce.", flash[:error]

      post admin_run_salesforce_query_path, params: { soql: SOQL }, as: :turbo_stream
      assert_redirected_to me_root_path
    end

    assert_empty fake.queries
    assert_equal 0, ActionLog.where(event: "salesforce-query").count
  end

  test "a person with neither role is turned away" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@outsider)

    with_fake_connector(fake) do
      get admin_salesforce_query_path
      assert_redirected_to me_root_path

      post admin_run_salesforce_query_path, params: { soql: SOQL }, as: :turbo_stream
      assert_redirected_to me_root_path
    end

    assert_empty fake.queries
  end

  test "a signed-out visitor is sent to sign in" do
    get admin_salesforce_query_path
    assert_redirected_to root_path

    post admin_run_salesforce_query_path, params: { soql: SOQL }, as: :turbo_stream
    assert_redirected_to root_path
  end

  # ------------------------------------------------------------- the run

  test "a run answers 200 with stream updates for the results and the live region" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "turbo-stream[action=update][target=?]", RESULTS
    assert_select "turbo-stream[action=update][target=live-region]"
    assert_equal [SOQL], fake.queries
  end

  test "records reach the page as flattened columns, with nulls spoken" do
    fake = FakeSalesforceConnector.new(query_results: [envelope(
      record("Id" => "a01", "Ranger_Info__r" => record({ "MailingCity" => "Example City" }, "Contact")),
      record("Id" => "a02", "Ranger_Info__r" => nil)
    )])
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "th", text: "Id"
      assert_select "th", text: "Ranger_Info__r.MailingCity"
      assert_select "th", text: "attributes", count: 0
      assert_select "td", text: "Example City"
      assert_select "td .sr-only", text: "null"
      assert_select "p", text: /\A2 records\.\s+In query order\.\z/
    end
  end

  test "a value that looks like markup arrives as text" do
    fake = FakeSalesforceConnector.new(query_results: [envelope(record("Name" => "<script>alert(1)</script>"))])
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_select "template script", count: 0
  end

  test "a query Salesforce refuses shows its reason and no table" do
    fake = FakeSalesforceConnector.new(query_results: [false])
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_response :success
    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "h3", text: "Salesforce Could Not Run the Query"
      assert_select "pre", text: "fake salesforce failure"
      assert_select "table", count: 0
    end
  end

  test "an error message that looks like markup arrives as text" do
    fake = FakeSalesforceConnector.new(query_results: [false])
    fake.define_singleton_method(:error_message) { "<b>x</b>" }
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_select "template b", count: 0
    assert_includes response.body, "&lt;b&gt;x&lt;/b&gt;"
  end

  test "a failed sign-in says so, sends no query, and points at the settings" do
    fake = FakeSalesforceConnector.new(auth_result: false)
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_empty fake.queries
    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "h3", text: "Could Not Sign In to Salesforce"
      assert_select "p", text: /No query was sent\. Ask an Admin to check the Salesforce settings/
    end
  end

  test "the reason drops the prefix the callout title already says" do
    fake = FakeSalesforceConnector.new(query_results: [false])
    fake.define_singleton_method(:error_message) { "Salesforce query failed: INVALID_FIELD: \nSELECT Bogus\n       ^" }
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "pre", text: "INVALID_FIELD: \nSELECT Bogus\n       ^"
      assert_select "p", text: "Check the query, then run it again."
    end
  end

  test "an answer cut short says how much more Salesforce holds" do
    fake = FakeSalesforceConnector.new(query_results: [
      envelope(record("Name" => "R-9001"), record("Name" => "R-9002"), total: 2500, done: false)
    ])
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "p", text: /\A2 of 2,500 records\./
      assert_select "[role=status]", text: /Salesforce has more records than it sent/
      assert_select "tbody tr", count: 2
    end
  end

  test "short values stay on one line and long text wraps in a column of its own" do
    essay = "To give back to the city that gave me so much, year after year, on the playa."
    fake = FakeSalesforceConnector.new(query_results: [envelope(record("Name" => "R-9001", "Why_Ranger__c" => essay))])
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "td.whitespace-nowrap", text: "R-9001"
      assert_select "td.whitespace-pre-line", text: essay
    end
  end

  test "the records scroll inside a pane, under column names that stay put" do
    fake = FakeSalesforceConnector.new(query_results: [envelope(record("Name" => "R-9001"))])
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_select "turbo-stream[target=?] template", RESULTS do
      # A plain table at every width: sideways scrolling is the intended reading.
      assert_select "table.responsive-table", count: 0
      assert_select "table" do |(table)|
        assert_includes table.parent["class"], "lg:max-h-[70vh] lg:overflow-y-auto"
      end
      assert_select "thead" do |(thead)|
        assert_includes thead["class"], TableHelper::PINNED_HEADER_CLASSES
      end
    end
  end

  test "each heading holds a button that sorts its column, and nothing claims a sort yet" do
    fake = FakeSalesforceConnector.new(query_results: [envelope(record("Name" => "R-9001", "Score__c" => 3))])
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "caption.sr-only", text: /column headings are buttons that sort the table/
      assert_select "th[data-sort-type=text] button[type=button][data-action='table-sort#sort']", text: "Name"
      assert_select "th[data-sort-type=number] button[data-action='table-sort#sort']", text: "Score__c"
      assert_select "th[aria-sort]", count: 0
      assert_select "[data-table-sort-target=status]", text: "In query order."
    end
  end

  test "a FIND runs as a search and shows which object each record is" do
    fake = FakeSalesforceConnector.new(query_results: [FakeSalesforceConnector.search_envelope(
      record({ "Id" => "003A", "LastName" => "Day" }, "Contact"), record("Id" => "a01A", "Name" => "R-9001")
    )])
    sign_in_as(@tech_ninja)

    with_fake_connector(fake) do
      post admin_run_salesforce_query_path, params: { soql: "FIND {Day}" }, as: :turbo_stream
    end

    assert_equal ["FIND {Day}"], fake.searches
    assert_empty fake.queries
    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "th", text: "attributes.type"
      assert_select "td", text: "Contact"
      assert_select "td", text: "Ranger__c"
      assert_select "p", text: /\A2 records\./
    end
  end

  test "a search that finds nothing says so in search terms" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@tech_ninja)

    with_fake_connector(fake) do
      post admin_run_salesforce_query_path, params: { soql: "FIND {Nobody}" }, as: :turbo_stream
    end

    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "p", text: /Salesforce found no records for this search\. Check the search term/
    end
  end

  test "SELECT COUNT() reports the count, never no records" do
    fake = FakeSalesforceConnector.new(query_results: [envelope(total: 42)])
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_select "turbo-stream[target=?] template", RESULTS do
      assert_select "p", text: "Salesforce counted 42 records."
      assert_select "table", count: 0
    end
  end

  test "nothing about the run is kept in the request log" do
    Setting.find_or_initialize_by(name: Setting::REQUEST_LOG_ENABLED).update!(value: "true")
    sign_in_as(@tech_ninja)

    run_query(FakeSalesforceConnector.new(query_results: [envelope(record("Name" => "R-9001"))]))

    entry = RequestLog.order(:id).last
    assert_equal "admin/salesforce-query", entry.url, "the run was recorded, so the nils below mean something"
    assert_nil entry.request_payload
    assert_nil entry.response_payload
  end

  test "each run writes one action log row with the query, never the records" do
    sign_in_as(@tech_ninja)

    run_query(FakeSalesforceConnector.new(query_results: [envelope(record("Name" => "R-9001"))]))

    rows = ActionLog.where(event: "salesforce-query").to_a
    assert_equal 1, rows.size
    assert_equal @tech_ninja.id, rows.first.person_id
    assert_equal({ "soql" => SOQL, "total" => 1 }, rows.first.data)
  end

  test "the run keeps a refused query out of the error log" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@tech_ninja)

    run_query(fake)

    assert_equal false, fake.log_rejections
  end

  test "the results heading says when the answers are canned" do
    sign_in_as(@tech_ninja)

    with_fake_connector(Salesforce::MockConnector.new) { get admin_salesforce_query_path }
    assert_select "section .badge", text: "Mock Data"

    with_fake_connector(FakeSalesforceConnector.new) { get admin_salesforce_query_path }
    assert_select "section .badge", count: 0
  end

  test "the Groundhog Day Server opens the page but never runs a query" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@tech_ninja)

    ENV["RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"] = "2026-04-16 12:00:00"
    begin
      with_fake_connector(fake) { get admin_salesforce_query_path }
      assert_response :success

      run_query(fake)
    ensure
      ENV.delete("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME")
    end

    assert_redirected_to me_root_path
    assert_match "Groundhog Day Server", flash[:error]
    assert_empty fake.queries
    assert_equal 0, ActionLog.where(event: "salesforce-query").count
  end

  test "a blank query is refused without asking Salesforce" do
    fake = FakeSalesforceConnector.new
    sign_in_as(@tech_ninja)

    with_fake_connector(fake) do
      post admin_run_salesforce_query_path, params: { soql: "  " }, as: :turbo_stream
    end

    assert_response :bad_request
    assert_empty fake.queries
  end

  private

  def run_query(fake)
    with_fake_connector(fake) do
      post admin_run_salesforce_query_path, params: { soql: SOQL }, as: :turbo_stream
    end
  end

  def record(fields, type = "Ranger__c")
    { "attributes" => { "type" => type, "url" => "/services/data/v57.0/sobjects/#{type}/x" } }.merge(fields)
  end

  def envelope(*records, total: records.size, done: nil)
    body = { totalSize: total, records: }
    body[:done] = done unless done.nil?
    JSON.parse(body.to_json, object_class: OpenStruct)
  end
end
