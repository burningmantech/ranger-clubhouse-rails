# frozen_string_literal: true

# Canned Salesforce responses for exercising /vc/application-import without
# credentials. Only reachable through Salesforce.connector, which requires
# Rails.env.development? plus the SF_MOCK_DATA environment variable — this
# class must never answer in production.
#
# The roster covers every outcome the page can render: clean imports (one of
# each applicant type, one recycled approved handle), a contact the
# integration user cannot see, a contact with every field blank, a missing
# BPGUID, and a record that fails validation on commit (blank email). Running
# Import and then Preview again shows the "already in the Clubhouse" bucket.
class Salesforce
  class MockConnector
    attr_reader :error_message

    def auth
      true
    end

    # Writebacks are recorded rather than sent. Account creation treats a false
    # return as a hard failure, so the mock always succeeds.
    #
    # @return [true]
    def obj_update(objname, objid, fields)
      updates << { objname:, objid:, fields: }
      true
    end

    def updates
      @updates ||= []
    end

    # The import issues two query shapes: the application list (paged via
    # OFFSET) and the batched contact lookup (recognizable by the
    # Ranger_Info__r fields). Everything is rebuilt through JSON so the
    # records are nested OpenStructs, exactly like a live response.
    #
    # @param soql [String]
    # @param log_rejections [Boolean] accepted to match Salesforce#soql_query;
    #   the mock never refuses a query, so it never logs one
    # @return [OpenStruct]
    def soql_query(soql, log_rejections: true)
      # Anything but a SELECT (a FIND goes to sosl_search) stands in for a query
      # Salesforce refuses, so the
      # Salesforce Query page's error can be seen without the live org. The
      # message has Salesforce's multi-line shape, caret line included.
      unless soql.match?(/\A\s*select\b/i)
        @error_message = "Salesforce query failed: MALFORMED_QUERY: \n#{soql.strip.lines.first.chomp}\n^\n" \
                         "ERROR at Row:1:Column:1\nunexpected token: '#{soql.split.first}'"
        return false
      end

      records =
        if soql.include?("Ranger_Info__r.")
          contact_records
        elsif soql.include?(" OFFSET ")
          []
        else
          application_records
        end

      JSON.parse({ totalSize: records.length, records: records }.to_json, object_class: OpenStruct)
    end

    # Two pages search. VC › BPGUID Lookup's statement returns Contacts only
    # (RETURNING Contact (...)), and gets the contacts that match its search
    # term -- none at all, so the zero state can be seen. Any other FIND, which
    # is the Salesforce Query page's, answers with the same mixed list -- three
    # applications and two contacts -- each naming its object type in
    # attributes, as Salesforce's search does.
    #
    # @param sosl [String]
    # @param log_rejections [Boolean] accepted to match Salesforce#sosl_search
    # @return [OpenStruct]
    def sosl_search(sosl, log_rejections: true)
      return contact_search(sosl) if sosl.include?("RETURNING Contact (")

      applications = application_records.first(3).map do |record|
        { attributes: { type: "Ranger__c" } }.merge(record.slice(:Id, :Name, :Applicant_First_Name__c, :Applicant_Last_Name__c))
      end
      contacts = [
        { attributes: { type: "Contact" }, Id: "003900000001", FirstName: "Sunny", LastName: "Day",
          Email: "sunny.day@example.com" },
        { attributes: { type: "Contact" }, Id: "003900000003", FirstName: "River", LastName: "Stone",
          Email: "river.stone@example.com" }
      ]

      JSON.parse({ searchRecords: applications + contacts }.to_json, object_class: OpenStruct)
    end

    private

    # The contacts whose names or emails hold the search term, unescaped, with
    # its * wildcards dropped and its case ignored.
    def contact_search(sosl)
      term = sosl[/\{(.*)\} RETURNING Contact \(/m, 1].to_s.gsub(/\\(.)/m, "\\1").delete("*").strip.downcase
      found = contact_search_records.select do |record|
        record.values_at(:FirstName, :LastName, :Email, :Burner_Profile_Email__c).compact.any? do |value|
          value.downcase.include?(term)
        end
      end

      JSON.parse({ searchRecords: found }.to_json, object_class: OpenStruct)
    end

    # Coherent with the applications below: the first Sunny Day, Dusty Trails
    # and River Stone carry their applications' BPGUIDs. The second Sunny Day
    # has none, so a row without a BPGUID can be seen.
    def contact_search_records
      [
        search_contact(first_name: "Sunny", last_name: "Day", email: "sunny.day@example.com",
                       burner_profile_email: "sunny.day@example.com", home_phone: "775-555-0101",
                       bpguid: "b7e2a1c0-0001-4000-9001-000000009001",
                       home_address: "9001 Example St\r\nApt 2, Example City, NV 99999, United States"),
        search_contact(first_name: "Sunny", last_name: "Day", email: "sunny.d@example.org", phone: "775-555-0111"),
        search_contact(first_name: "Dusty", last_name: "Trails", email: "dusty.trails@example.com",
                       burner_profile_email: "dusty@example.net", home_phone: "775-555-0102",
                       bpguid: "b7e2a1c0-0002-4000-9002-000000009002", home_address: ""),
        search_contact(first_name: "River", last_name: "Stone", email: "river.stone@example.com",
                       burner_profile_email: "river.stone@example.com", phone: "775-555-0104",
                       bpguid: "b7e2a1c0-0003-4000-9003-000000009003",
                       home_address: "9003 Example St, Example City, OR 99999, United States")
      ]
    end

    # Every field the BPGUID Lookup statement returns, null where Salesforce
    # would send null.
    def search_contact(first_name:, last_name:, email:, burner_profile_email: nil, home_phone: nil, phone: nil,
                       bpguid: nil, home_address: nil)
      {
        attributes: { type: "Contact" },
        FirstName: first_name,
        LastName: last_name,
        Email: email,
        Burner_Profile_Email__c: burner_profile_email,
        HomePhone: home_phone,
        Phone: phone,
        BPGUID__c: bpguid,
        npe01__Home_Address__c: home_address
      }
    end

    def application_records
      [
        application(id: "a019001", name: "R-9001", first_name: "Sunny", last_name: "Day",
                    email: "sunny.day@example.com", bpguid: "b7e2a1c0-0001-4000-9001-000000009001",
                    handles: "Sunburst\nDaybreak", comments: "Solid application, references check out.",
                    why_comments: "Wants to give back after years of attending."),
        application(id: "a019002", name: "R-9002", first_name: "Dusty", last_name: "Trails",
                    email: "dusty.trails@example.com", bpguid: "b7e2a1c0-0002-4000-9002-000000009002",
                    type: "Prospective New Volunteer - Black Rock Ranger Redux",
                    status: "In VC Intake Process", approved_handle: "Dustoff (2019)",
                    experience: "Yes BRC2"),
        application(id: "a019003", name: "R-9003", first_name: "River", last_name: "Stone",
                    email: "river.stone@example.com", bpguid: "b7e2a1c0-0003-4000-9003-000000009003",
                    type: "Training Auditor", regional: "Ranger with Gerlach Regionals since 2021",
                    regional_callsign: "Pebble"),
        application(id: "a019004", name: "R-9004", first_name: "Cloud", last_name: "Nine",
                    email: "cloud.nine@example.com", bpguid: "b7e2a1c0-0004-4000-9004-000000009004"),
        application(id: "a019005", name: "R-9005", first_name: "Echo", last_name: "Chamber",
                    email: "echo.chamber@example.com", bpguid: "b7e2a1c0-0005-4000-9005-000000009005"),
        application(id: "a019006", name: "R-9006", first_name: "Drift", last_name: "Wood",
                    email: "drift.wood@example.com", bpguid: ""),
        application(id: "a019007", name: "R-9007", first_name: "Broken", last_name: "Mail",
                    email: "", bpguid: "b7e2a1c0-0007-4000-9007-000000009007")
      ]
    end

    # R-9004 is deliberately absent (inaccessible contact); R-9005 is present
    # with every field blank.
    def contact_records
      [
        contact(id: "a019001", sfuid: "005900000001", street: "9001 Example St\r\nApt 2",
                city: "Example City", state: "NV", postal_code: "99999",
                phone: "", mobile: "775-555-0101",
                emergency: ["Moon Beam", "775-555-0199", "partner"]),
        contact(id: "a019002", sfuid: "005900000002", street: "9002 Example St",
                city: "Example City", state: "NV", postal_code: "99999",
                phone: "775-555-0102", mobile: "", years: "2015;2017;2019"),
        contact(id: "a019003", sfuid: "005900000003", street: "9003 Example St",
                city: "Example City", state: "OR", postal_code: "99999",
                phone: "775-555-0103", mobile: "775-555-0104", years: "2022;2023"),
        contact(id: "a019005", sfuid: "", street: "", city: "", state: "", postal_code: ""),
        contact(id: "a019006", sfuid: "005900000006", street: "9006 Example St",
                city: "Example City", state: "CA", postal_code: "99999", phone: "775-555-0106"),
        contact(id: "a019007", sfuid: "005900000007", street: "9007 Example St",
                city: "Example City", state: "NV", postal_code: "99999", phone: "775-555-0107")
      ]
    end

    def application(id:, name:, first_name:, last_name:, email:, bpguid:,
                    type: "Prospective New Volunteer - Black Rock Ranger",
                    status: "Not Yet Started", approved_handle: "", handles: "",
                    comments: "", why_comments: "", experience: "Never",
                    regional: "", regional_callsign: "")
      {
        Id: id,
        Name: name,
        CH_UID__c: "",
        Applicant_BPGUID__c: bpguid,
        Applicant_First_Name__c: first_name,
        Applicant_Last_Name__c: last_name,
        Contact_Email__c: email,
        Known_Prospective_Volunteer_Names__c: "",
        Known_Rangers_Names__c: "",
        Ranger_Applicant_Type__c: type,
        Submit_Radio_Call_Signs__c: handles,
        VC_Approved_Radio_Call_Sign__c: approved_handle,
        VC_Comments__c: comments,
        VC_Event_Year__c: Current.year.to_s,
        VC_Status__c: status,
        Why_Ranger__c: "I want to serve the community that shaped me.",
        Why_Ranger_Comments__c: why_comments,
        Regional_Ranger_Experience__c: regional,
        Current_Regional_Callsign__c: regional_callsign,
        Ranger_Info_Over_18_Check__c: "Yes",
        Attended_Burning_Man_Twice__c: experience
      }
    end

    def contact(id:, sfuid:, street:, city:, state:, postal_code:,
                phone: "", mobile: "", years: "", emergency: [])
      {
        Id: id,
        Ranger_Info__r: {
          Id: "003#{id}",
          Years_Attended_Burning_Man__c: years,
          MailingStreet: street,
          MailingCity: city,
          MailingState: state,
          MailingCountry: city.present? ? "United States" : "",
          MailingPostalCode: postal_code,
          MailingAddress: "",
          Phone: phone,
          MobilePhone: mobile,
          OtherPhone: "",
          SFUID__c: sfuid,
          Emergency_Contact_Name__c: emergency[0].to_s,
          Emergency_Contact_Phone__c: emergency[1].to_s,
          Emergency_Contact_Relationship__c: emergency[2].to_s
        }
      }
    end
  end
end
