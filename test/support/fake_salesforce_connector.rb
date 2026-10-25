# frozen_string_literal: true

require "ostruct"

# Stand-in for the Salesforce connector, ported from the Laravel
# FakeSalesforceConnector test support class. Records every SOQL query issued
# and plays back a queue of canned results; once the queue drains, every
# remaining query gets an empty envelope, which also ends pagination. Queue
# `false` entries to simulate query failures.
class FakeSalesforceConnector
  attr_reader :auth_result, :error_message, :log_rejections, :queries, :searches, :updates

  def initialize(auth_result: true, query_results: [], update_results: [])
    @auth_result = auth_result
    @query_results = query_results
    @update_results = update_results
    @error_message = "fake salesforce failure"
    @queries = []
    @searches = []
    @updates = []
  end

  def auth
    auth_result
  end

  # log_rejections is kept so a test can pin what the caller asked for.
  def soql_query(soql, log_rejections: true)
    @queries << soql
    @log_rejections = log_rejections
    return @query_results.shift unless @query_results.empty?

    self.class.envelope
  end

  # SOSL searches are recorded apart from queries and play back the same
  # query_results queue; once it drains, a search finds nothing.
  def sosl_search(sosl, log_rejections: true)
    @searches << sosl
    @log_rejections = log_rejections
    return @query_results.shift unless @query_results.empty?

    self.class.search_envelope
  end

  # Records every writeback and plays back the update_results queue; once it
  # drains, updates succeed. Queue `false` entries to simulate failures.
  def obj_update(objname, objid, fields)
    @updates << { objname:, objid:, fields: }
    return @update_results.shift unless @update_results.empty?

    true
  end

  class << self
    # Build a query response envelope of nested OpenStructs, exactly like a
    # decoded live Salesforce response.
    def envelope(*records)
      JSON.parse({ totalSize: records.length, records: records }.to_json, object_class: OpenStruct)
    end

    # A search response: no totalSize, no paging, just the records.
    def search_envelope(*records)
      JSON.parse({ searchRecords: records }.to_json, object_class: OpenStruct)
    end

    # A complete Ranger__c application row; override per test.
    def application_record(overrides = {})
      {
        "Id" => "a01SF001",
        "Name" => "R-5001",
        "CH_UID__c" => "",
        "Applicant_BPGUID__c" => "SF-BPGUID-5001",
        "Applicant_First_Name__c" => "Terra",
        "Applicant_Last_Name__c" => "Firma",
        "Contact_Email__c" => "terra.firma@example.com",
        "Known_Prospective_Volunteer_Names__c" => "",
        "Known_Rangers_Names__c" => "",
        "Ranger_Applicant_Type__c" => "Prospective New Volunteer - Black Rock Ranger",
        "Submit_Radio_Call_Signs__c" => "Terra\nFirma",
        "VC_Approved_Radio_Call_Sign__c" => "",
        "VC_Comments__c" => "",
        "VC_Event_Year__c" => "2031",
        "VC_Status__c" => "Not Yet Started",
        "Why_Ranger__c" => "To serve the city.",
        "Why_Ranger_Comments__c" => "",
        "Regional_Ranger_Experience__c" => "",
        "Current_Regional_Callsign__c" => "",
        "Ranger_Info_Over_18_Check__c" => "Yes",
        "Attended_Burning_Man_Twice__c" => "Yes BRC2"
      }.merge(overrides)
    end

    # A Contact as VC › BPGUID Lookup's search returns it: every field its
    # RETURNING list names, and the attributes Salesforce adds; override per test.
    def contact_search_record(overrides = {})
      {
        "attributes" => { "type" => "Contact" },
        "FirstName" => "Sunny",
        "LastName" => "Day",
        "Email" => "sunny.day@example.com",
        "Burner_Profile_Email__c" => "sunny@example.net",
        "HomePhone" => "775-555-0101",
        "Phone" => "775-555-0111",
        "BPGUID__c" => "b7e2a1c0-0001-4000-9001-000000009001",
        "npe01__Home_Address__c" => "9001 Example St, Example City, NV 99999, United States"
      }.merge(overrides)
    end

    # A batched contact-lookup row for the given Ranger__c id. Overrides are
    # merged into the nested Ranger_Info__r contact fields.
    def contact_record(id, overrides = {})
      {
        "Id" => id,
        "Ranger_Info__r" => {
          "Id" => "003#{id}",
          "Years_Attended_Burning_Man__c" => "2022;2023",
          "MailingStreet" => "1 Example St",
          "MailingCity" => "Example City",
          "MailingState" => "NV",
          "MailingCountry" => "US",
          "MailingPostalCode" => "99999",
          "MailingAddress" => "",
          "Phone" => "775-555-0100",
          "MobilePhone" => "",
          "OtherPhone" => "",
          "SFUID__c" => "005SF001",
          "Emergency_Contact_Name__c" => "",
          "Emergency_Contact_Phone__c" => "",
          "Emergency_Contact_Relationship__c" => ""
        }.merge(overrides)
      }
    end

    # A contact row whose Ranger_Info__r relationship came back null.
    def contact_record_without_ranger_info(id)
      { "Id" => id, "Ranger_Info__r" => nil }
    end
  end
end

# Swap the connector Salesforce.connector hands out for a fake, restoring the
# original afterwards. The swap is process-wide, so it reaches the server thread
# of a system test too.
module FakeSalesforceConnectorHelper
  def with_fake_connector(fake)
    original = Salesforce.method(:connector)
    Salesforce.define_singleton_method(:connector) { fake }
    yield
  ensure
    Salesforce.define_singleton_method(:connector, original)
  end
end
