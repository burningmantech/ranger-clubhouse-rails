# frozen_string_literal: true

require "test_helper"

class Salesforce::MockConnectorTest < ActiveSupport::TestCase
  test "anything but a SELECT is refused the way Salesforce refuses a malformed query" do
    mock = Salesforce::MockConnector.new

    assert_equal false, mock.soql_query("SELEKT Id FROM Ranger__c")
    assert_equal "Salesforce query failed: MALFORMED_QUERY: \nSELEKT Id FROM Ranger__c\n^\n" \
                 "ERROR at Row:1:Column:1\nunexpected token: 'SELEKT'", mock.error_message
  end

  test "a SELECT still answers with the canned applications, whatever its case" do
    assert_equal 7, Salesforce::MockConnector.new.soql_query("select Id from Ranger__c").records.size
  end

  # L12
  test "a search answers with applications and contacts, each naming its object" do
    found = Salesforce::MockConnector.new.sosl_search("FIND {Sunny}").searchRecords

    assert_equal %w[Ranger__c Ranger__c Ranger__c Contact Contact], found.map { |record| record.attributes.type }
  end

  # L9
  test "the bpguid lookup's search answers only the contacts that match, with every field it returns" do
    found = contact_search("sunny")

    assert_equal %w[Contact Contact], found.map { |record| record.attributes.type }
    assert_equal ["sunny.day@example.com", "sunny.d@example.org"], found.map(&:Email)
    found.each do |record|
      assert_equal SalesforceContactSearch::FIELDS.sort, (record.to_h.keys.map(&:to_s) - ["attributes"]).sort
    end
  end

  # L10: the term reaches the mock escaped, as Salesforce.sosl_escape sent it.
  test "the bpguid lookup's search drops the wildcard and the escapes before matching" do
    assert_equal ["sunny.day@example.com", "sunny.d@example.org"], contact_search("sun*").map(&:Email)
    assert_equal ["river.stone@example.com"], contact_search("river\\.stone@example\\.com").map(&:Email)
    # The Burner Profile email, in another case.
    assert_equal ["dusty.trails@example.com"], contact_search("DUSTY@example.net").map(&:Email)
  end

  # L11
  test "the bpguid lookup's search can find nobody" do
    assert_equal [], contact_search("nobody")
  end

  private

  def contact_search(term)
    statement = "FIND {#{term}} RETURNING Contact (#{SalesforceContactSearch::FIELDS.join(',')})"
    Salesforce::MockConnector.new.sosl_search(statement).searchRecords
  end
end
