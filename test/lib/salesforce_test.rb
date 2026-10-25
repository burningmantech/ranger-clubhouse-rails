# frozen_string_literal: true

require "test_helper"
require "ostruct"

# Unit tests for the Salesforce connector. These never touch the network:
# every request goes through the execute_request seam, which is swapped for
# a queue of response doubles, and ErrorLog is silenced on the failure paths.
class SalesforceTest < ActiveSupport::TestCase
  include ErrorLogTestHelper

  ResponseDouble = Struct.new(:code, :body, keyword_init: true)

  TOKEN_BODY = {
    access_token: "token-123",
    instance_url: "https://na1.example"
  }.to_json

  # ---- soql_quote ----

  test "soql_quote wraps a plain value" do
    assert_equal "'a01ABC'", Salesforce.soql_quote("a01ABC")
  end

  test "soql_quote escapes quotes and backslashes" do
    assert_equal "'a\\'01'", Salesforce.soql_quote("a'01")
    assert_equal "'a\\\\01'", Salesforce.soql_quote("a\\01")
  end

  # ---- sosl_escape ----

  # K1: the reference's 19 reserved characters, less the * the search keeps.
  test "sosl_escape backslash-escapes every reserved character but the wildcard" do
    reserved = ["?", "&", "|", "!", "{", "}", "[", "]", "(", ")", "^", "~", ":", "\\", "\"", "'", "+", "-"]
    assert_equal 18, reserved.uniq.size

    reserved.each do |character|
      assert_equal "a\\#{character}b", Salesforce.sosl_escape("a#{character}b"), "#{character} is reserved"
    end

    assert_equal "a\\?b*", Salesforce.sosl_escape("a?b*")
    assert_equal "sunny.day@example.com", Salesforce.sosl_escape("sunny.day@example.com")
    assert_equal "*tone smi*", Salesforce.sosl_escape("*tone smi*")
  end

  # K2: typed text cannot close the braces or add a clause, and a backslash is
  # escaped exactly once, so it cannot cancel the escape after it.
  test "sosl_escape keeps typed text inside the braces as one search term" do
    assert_equal "x\\} IN EMAIL FIELDS RETURNING User\\(Id, Username\\) LIMIT 2000 //\\{",
                 Salesforce.sosl_escape("x} IN EMAIL FIELDS RETURNING User(Id, Username) LIMIT 2000 //{")
    assert_equal "a\\\\\\}b", Salesforce.sosl_escape("a\\}b")
  end

  # ---- auth ----

  test "auth fails without any HTTP call when settings are blank" do
    sf = Salesforce.new
    stub_requests(sf, [])

    assert_not sf.auth
    assert_match "Salesforce settings are blank", sf.error_message
    assert_match "SFprdAuthUrl", sf.error_message
    assert_match "SFprdPassword", sf.error_message
  end

  test "auth posts the password grant and stores the token" do
    create_sf_settings(auth_url: "https://auth.example/")
    sf = Salesforce.new
    captured = stub_requests(sf, [ResponseDouble.new(code: "200", body: TOKEN_BODY)])

    assert sf.auth
    assert_equal "https://na1.example", sf.instance_url

    uri, request = captured.first
    assert_equal "https://auth.example/services/oauth2/token", uri.to_s
    body = request.body
    assert_includes body, "grant_type=password"
    assert_includes body, "client_id=client-id"
    assert_includes body, "username=sf-user"
  end

  test "auth failure surfaces the OAuth error payload" do
    create_sf_settings
    sf = Salesforce.new
    stub_requests(sf, [ResponseDouble.new(
      code: "400", body: { error: "invalid_grant", error_description: "authentication failure" }.to_json
    )])

    silence_error_log do |calls|
      assert_not sf.auth
      assert_equal "Salesforce authentication failed: invalid_grant: authentication failure", sf.error_message
      assert_equal "salesforce-request-exception", calls.first[:type]
    end
  end

  test "auth rescues network failures and never logs credentials" do
    create_sf_settings
    sf = Salesforce.new
    sf.define_singleton_method(:execute_request) { |_uri, _request| raise SocketError, "host unreachable" }

    silence_error_log do |calls|
      assert_not sf.auth
      assert_match "Failed to retrieve the authentication token: host unreachable", sf.error_message

      call = calls.first
      assert_equal :record_exception, call[:method]
      assert_equal "salesforce-auth-exception", call[:args][1]
      logged = call[:kwargs].to_json
      assert_no_match(/sf-password-token/, logged)
      assert_no_match(/client-secret/, logged)
    end
  end

  test "auth fails on an undecodable token response" do
    create_sf_settings
    sf = Salesforce.new
    stub_requests(sf, [ResponseDouble.new(code: "200", body: "<html>gateway timeout</html>")])

    silence_error_log do |calls|
      assert_not sf.auth
      assert_match "Failed to decode the Salesforce response", sf.error_message
      assert_equal :record_exception, calls.first[:method]
      assert_equal "salesforce-json-exception", calls.first[:args][1]
    end
  end

  # ---- soql_query ----

  test "soql_query returns the decoded envelope" do
    sf = authed_connector(ResponseDouble.new(
      code: "200", body: { totalSize: 1, records: [{ Id: "a01" }] }.to_json
    ))

    result = sf.soql_query("SELECT Id FROM Ranger__c")
    assert_equal 1, result.records.length
    assert_equal "a01", result.records.first.Id
  end

  test "soql_query sends the bearer token and the query" do
    captured = nil
    sf = authed_connector(ResponseDouble.new(code: "200", body: { totalSize: 0, records: [] }.to_json)) do |c|
      captured = c
    end
    sf.soql_query("SELECT Id FROM Ranger__c")

    uri, request = captured.last
    assert_includes uri.to_s, "https://na1.example/services/data/v57.0/query?q=SELECT"
    assert_equal "Bearer token-123", request["Authorization"]
  end

  test "soql_query surfaces a Salesforce error response" do
    sf = authed_connector(ResponseDouble.new(
      code: "400", body: [{ message: "No such column", errorCode: "INVALID_FIELD" }].to_json
    ))

    silence_error_log do |calls|
      assert_equal false, sf.soql_query("SELECT Bogus FROM Ranger__c")
      assert_match "INVALID_FIELD", sf.error_message
      assert_equal "salesforce-query-exception", calls.first[:type]
    end
  end

  test "soql_query can keep a refused query out of the error log" do
    sf = authed_connector(ResponseDouble.new(
      code: "400", body: [{ message: "No such column", errorCode: "INVALID_FIELD" }].to_json
    ))

    silence_error_log do |calls|
      assert_equal false, sf.soql_query("SELECT Bogus FROM Ranger__c", log_rejections: false)
      assert_match "INVALID_FIELD", sf.error_message
      assert_empty calls
    end
  end

  test "soql_query logs every failure other than a refused query, even when asked not to log refusals" do
    body = [{ message: "Session expired", errorCode: "INVALID_SESSION_ID" }].to_json
    sf = authed_connector(nil)

    %w[401 500].each do |code|
      sf.define_singleton_method(:execute_request) { |_uri, _request| ResponseDouble.new(code:, body:) }

      silence_error_log do |calls|
        assert_equal false, sf.soql_query("SELECT Id FROM Ranger__c", log_rejections: false)
        assert_equal ["salesforce-query-exception"], calls.map { |call| call[:type] }, "status #{code}"
      end
    end
  end

  # ---- sosl_search ----

  test "sosl_search sends the search to the search resource and returns its records" do
    captured = nil
    body = { searchRecords: [{ attributes: { type: "Contact", url: "/x" }, Id: "003" }] }.to_json
    sf = authed_connector(ResponseDouble.new(code: "200", body:)) { |c| captured = c }

    result = sf.sosl_search("FIND {Sunny} RETURNING Contact(Id)")

    assert_equal "Contact", result.searchRecords.first.attributes.type
    uri, request = captured.last
    assert_includes uri.to_s, "https://na1.example/services/data/v57.0/search/?q=FIND+%7BSunny%7D"
    assert_equal "Bearer token-123", request["Authorization"]
  end

  test "sosl_search can keep a refused search out of the error log" do
    sf = authed_connector(ResponseDouble.new(
      code: "400", body: [{ message: "unexpected token: 'FIND'", errorCode: "MALFORMED_SEARCH" }].to_json
    ))

    silence_error_log do |calls|
      assert_equal false, sf.sosl_search("FIND Sunny", log_rejections: false)
      assert_match "MALFORMED_SEARCH", sf.error_message
      assert_empty calls
    end
  end

  test "sosl_search rejects an answer without a searchRecords list" do
    sf = authed_connector(ResponseDouble.new(code: "200", body: { totalSize: 0, records: [] }.to_json))

    silence_error_log do |calls|
      assert_equal false, sf.sosl_search("FIND {Sunny}")
      assert_equal "Salesforce search returned an unexpected response", sf.error_message
      assert_equal "salesforce-query-failed", calls.first[:type]
    end
  end

  test "soql_query rescues network failures" do
    sf = authed_connector(nil)
    sf.define_singleton_method(:execute_request) { |_uri, _request| raise Net::ReadTimeout }

    silence_error_log do |calls|
      assert_equal false, sf.soql_query("SELECT Id FROM Ranger__c")
      assert_match "Salesforce query failed", sf.error_message
      assert_equal "salesforce-query-exception", calls.first[:args][1]
    end
  end

  test "soql_query rejects a response without a records list" do
    sf = authed_connector(ResponseDouble.new(code: "200", body: "[]"))

    silence_error_log do |calls|
      assert_equal false, sf.soql_query("SELECT Id FROM Ranger__c")
      assert_equal "Salesforce query returned an unexpected response", sf.error_message
      assert_equal "salesforce-query-failed", calls.first[:type]
    end
  end

  # ---- obj_update ----

  test "obj_update patches the record with a JSON body" do
    captured = nil
    sf = authed_connector(ResponseDouble.new(code: "204", body: "")) { |c| captured = c }

    assert sf.obj_update("Ranger__c", "a01SF001", { "CH_UID__c" => "42" })

    uri, request = captured.last
    assert_equal "https://na1.example/services/data/v57.0/sobjects/Ranger__c/a01SF001", uri.to_s
    assert_equal "PATCH", request.method
    assert_equal "Bearer token-123", request["Authorization"]
    assert_equal "application/json", request["Content-Type"]
    assert_equal({ "CH_UID__c" => "42" }, JSON.parse(request.body))
  end

  test "obj_update surfaces a Salesforce error response" do
    body = [{ errorCode: "MALFORMED_ID", message: "bad id" }].to_json
    sf = authed_connector(ResponseDouble.new(code: "400", body: body))

    silence_error_log do |calls|
      assert_equal false, sf.obj_update("Ranger__c", "nope", { "CH_UID__c" => "42" })
      assert_match "MALFORMED_ID: bad id", sf.error_message
      assert_equal "salesforce-update-exception", calls.first[:type]
      # The written fields carry applicant data and stay out of the error log.
      assert_no_match(/CH_UID__c/, calls.first[:kwargs].to_json)
    end
  end

  test "obj_update survives a dropped connection" do
    sf = authed_connector(nil)
    sf.define_singleton_method(:execute_request) { |_uri, _request| raise SocketError, "no route to host" }

    silence_error_log do |calls|
      assert_equal false, sf.obj_update("Ranger__c", "a01SF001", {})
      assert_match "Salesforce update failed: no route to host", sf.error_message
      assert_equal "salesforce-update-exception", calls.first[:args][1]
    end
  end

  private

  def create_sf_settings(auth_url: "https://auth.example")
    {
      Setting::SF_PRD_AUTH_URL => auth_url,
      Setting::SF_PRD_CLIENT_ID => "client-id",
      Setting::SF_PRD_CLIENT_SECRET => "client-secret",
      Setting::SF_PRD_USERNAME => "sf-user",
      Setting::SF_PRD_PASSWORD => "sf-password-token"
    }.each { |name, value| Setting.create!(name: name, value: value) }
  end

  # Swap the execute_request seam for a response queue; returns the captured
  # [uri, request] pairs.
  def stub_requests(sf, responses)
    captured = []
    sf.define_singleton_method(:execute_request) do |uri, request|
      captured << [uri, request]
      responses.shift || raise("no stubbed response left")
    end
    captured
  end

  # A connector that has already authenticated, with one queued response for
  # the query under test. Yields the capture list when a block is given.
  def authed_connector(query_response)
    create_sf_settings
    sf = Salesforce.new
    responses = [ResponseDouble.new(code: "200", body: TOKEN_BODY)]
    responses << query_response if query_response
    captured = stub_requests(sf, responses)
    yield captured if block_given?
    assert sf.auth, "test setup: auth should succeed"
    sf
  end
end
