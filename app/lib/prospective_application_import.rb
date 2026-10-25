# frozen_string_literal: true

# Import "View 1 - Check Qualifications" Ranger applications from Salesforce
# into prospective_application records. Ported from the Laravel
# App\Lib\ProspectiveApplicationImport class.
#
# The run pulls applications in pages of 400, and for each page issues a
# second batched query for the applicant contact (Ranger_Info__r) fields.
# The contact query runs WITH USER_MODE: a contact the integration account
# cannot see is simply absent from the results, which classifies the record
# as "contact inaccessible" rather than failing the run.
#
# Results land in four buckets: new applications (unsaved on preview, saved
# on commit), applications already in the Clubhouse for (current year,
# salesforce_name), records rejected before save (query_failures), and
# records whose save failed (create_failures). A Salesforce failure mid-run
# stops pagination but keeps the buckets already filled — the page renders
# partial results plus the api_error banner.
#
# Commit writes each record in its own transaction: the application row, an
# "imported" audit log entry, and up to two notes taken from the Salesforce
# VC comment fields. No emails are sent and nothing is written back to
# Salesforce on this path.
class ProspectiveApplicationImport
  PAGE_LIMIT = 400

  STATUS_MAP = {
    "Not Yet Started" => ProspectiveApplication::STATUS_PENDING,
    "In VC Intake Process" => ProspectiveApplication::STATUS_PENDING,
    "Released to Upload" => ProspectiveApplication::STATUS_APPROVED,
    "FLAG - See VC Notes" => ProspectiveApplication::STATUS_HOLD_QUALIFICATION_ISSUE,
    "Clubhouse Import Failed" => ProspectiveApplication::STATUS_CREATED,
    "Clubhouse Record Not Updated" => ProspectiveApplication::STATUS_CREATED,
    "Clubhouse Record Updated" => ProspectiveApplication::STATUS_CREATED,
    "Clubhouse Record Created" => ProspectiveApplication::STATUS_CREATED,
    "STOP - Duplicate Record" => ProspectiveApplication::STATUS_DUPLICATE,
    "STOP - See Notes" => ProspectiveApplication::STATUS_REJECT_UNQUALIFIED,
    "STOP - Not Qualified" => ProspectiveApplication::STATUS_REJECT_UNQUALIFIED,
    "STOP - UBERBONK" => ProspectiveApplication::STATUS_REJECT_UBERBONKED
  }.freeze
  # "STOP - Past Prospective" is deliberately absent: it maps on whether the
  # application already points at a Clubhouse account (see .status_for).

  EXPERIENCE_MAP = {
    "Never" => ProspectiveApplication::EXPERIENCE_NONE,
    "No" => ProspectiveApplication::EXPERIENCE_NONE,
    "Yes BRC1" => ProspectiveApplication::EXPERIENCE_BRC1,
    "Yes BRC1-RR1" => ProspectiveApplication::EXPERIENCE_BRC1R1,
    "Yes BRC2" => ProspectiveApplication::EXPERIENCE_BRC2,
    "Yes" => ProspectiveApplication::EXPERIENCE_BRC1
  }.freeze

  # Salesforce field -> prospective_application column. The source used one
  # array where a numeric index meant "queried but not column-mapped"; the
  # query-only fields live in their own lists here instead.
  APPLICATION_FIELD_MAP = {
    "Id" => "salesforce_id",
    "Name" => "salesforce_name",
    "CH_UID__c" => "person_id",
    "Applicant_BPGUID__c" => "bpguid",
    "Applicant_First_Name__c" => "first_name",
    "Applicant_Last_Name__c" => "last_name",
    "Contact_Email__c" => "email",
    "Known_Prospective_Volunteer_Names__c" => "known_applicants",
    "Known_Rangers_Names__c" => "known_rangers",
    "Submit_Radio_Call_Signs__c" => "handles",
    "VC_Approved_Radio_Call_Sign__c" => "approved_handle",
    "Why_Ranger__c" => "why_volunteer",
    "Regional_Ranger_Experience__c" => "regional_experience",
    "Current_Regional_Callsign__c" => "regional_callsign"
  }.freeze

  # VC_Event_Year__c is queried for parity but never stored: imports always
  # land in the current event year.
  APPLICATION_QUERY_ONLY_FIELDS = %w[
    Ranger_Applicant_Type__c
    VC_Comments__c
    VC_Status__c
    Why_Ranger_Comments__c
    Ranger_Info_Over_18_Check__c
    Attended_Burning_Man_Twice__c
    VC_Event_Year__c
  ].freeze

  # Contact (Ranger_Info__r) field -> column. Bare field names; the
  # relationship prefix is added only when building the SOQL. The mapped
  # fields double as the "is this contact all blank?" check.
  CONTACT_FIELD_MAP = {
    "Years_Attended_Burning_Man__c" => "events_attended",
    "MailingStreet" => "street",
    "MailingCity" => "city",
    "MailingState" => "state",
    "MailingCountry" => "country",
    "MailingPostalCode" => "postal_code",
    "SFUID__c" => "sfuid"
  }.freeze

  CONTACT_QUERY_ONLY_FIELDS = %w[
    MailingAddress
    Phone
    MobilePhone
    OtherPhone
    Emergency_Contact_Name__c
    Emergency_Contact_Phone__c
    Emergency_Contact_Relationship__c
  ].freeze

  # First non-blank wins.
  PHONE_FIELDS = %w[Phone MobilePhone OtherPhone].freeze

  APPLICANT_TYPES = [
    "Prospective New Volunteer - Black Rock Ranger",
    "Prospective New Volunteer - Black Rock Ranger Redux",
    "Training Auditor",
    "Black Rock Ranger"
  ].freeze

  # Approved handles in the recycled "Handle (YYYY)" format are historical
  # leftovers, not approvals — blank them on import.
  RECYCLED_HANDLE_REGEXP = /\A.*\(\d+\)\s*\z/

  ERROR_LABELS = {
    contact_blank: "Contact record accessible but all fields are blank",
    contact_inaccessible: "Contact record is inaccessible",
    missing_bpguid: "BPGUID is missing or inaccessible",
    invalid: "Clubhouse application record failed to validate",
    create_failure: "Clubhouse application record creation failed"
  }.freeze

  # A record that could not be imported. application is the unsaved
  # ProspectiveApplication carrying whatever fields were extracted before the
  # record was rejected; message holds validation or exception detail meant
  # only for the page (never the error log).
  Failure = Struct.new(:application, :error, :message, :contact_id, keyword_init: true) do
    def label
      ERROR_LABELS[error] || "Unknown error [#{error}]"
    end
  end

  attr_reader :connector, :new_applications, :existing_applications,
              :query_failures, :create_failures, :api_error

  def initialize(connector: Salesforce.connector)
    @connector = connector
    @new_applications = []
    @existing_applications = []
    @query_failures = []
    @create_failures = []
    @api_error = nil
  end

  # @return [Boolean]
  def auth
    connector.auth
  end

  # @return [String, nil]
  def auth_error
    connector.error_message
  end

  # Pull every unprocessed View 1 application and fill the result buckets.
  # Preview (commit: false) runs the identical pipeline but saves nothing.
  #
  # @param commit [Boolean]
  # @return [void]
  def import_unprocessed(commit: false)
    offset = 0
    loop do
      page = run_list_query(offset)
      break if page == false || page.records.empty?

      existing_by_name = existing_applications_by_name(page.records)
      contacts_by_id = query_contact_records(page.records.map(&:Id))
      page.records.each do |sf_row|
        import_application(sf_row, contacts_by_id[sf_row.Id], existing_by_name, commit:)
      end

      offset += page.records.length
    end
  end

  class << self
    # Map the Salesforce VC status to an application status. Unmapped
    # statuses fall through to pending so a new Salesforce pick-list value
    # never breaks the import.
    def status_for(sf_status, person_id)
      if sf_status == "STOP - Past Prospective"
        person_id.present? ? ProspectiveApplication::STATUS_CREATED : ProspectiveApplication::STATUS_PENDING
      else
        STATUS_MAP[sf_status] || ProspectiveApplication::STATUS_PENDING
      end
    end

    def experience_for(value)
      EXPERIENCE_MAP[value] || ProspectiveApplication::EXPERIENCE_NONE
    end

    # Assemble "Name (relationship) phone number", dropping blank parts.
    def emergency_contact_from(ranger_info)
      name = sanitize_field(ranger_info, "Emergency_Contact_Name__c")
      relationship = sanitize_field(ranger_info, "Emergency_Contact_Relationship__c")
      phone = sanitize_field(ranger_info, "Emergency_Contact_Phone__c")

      parts = []
      parts << name if name.present?
      parts << "(#{relationship})" if relationship.present?
      parts << "phone #{phone}" if phone.present?
      parts.join(" ")
    end

    def first_phone(ranger_info)
      PHONE_FIELDS.each do |field|
        value = sanitize_field(ranger_info, field)
        return value if value.present?
      end
      ""
    end

    def sanitize_street(street)
      street.to_s.delete("\r").tr("\n", " ").strip
    end

    # Read a possibly-absent field off a Salesforce OpenStruct record.
    def sanitize_field(sf_obj, field)
      sf_obj[field].to_s.strip
    end

    def recycled_handle?(handle)
      handle.to_s.match?(RECYCLED_HANDLE_REGEXP)
    end

    # Copy mapped Salesforce fields onto the application. Blank values are
    # stored as "" (most columns are NOT NULL); integer columns cast "" to
    # nil on their own.
    def extract_fields(field_map, sf_obj, application)
      field_map.each do |sf_field, column|
        value = sf_obj[sf_field]
        application[column] = value.presence || ""
      end
    end

    # True when every mapped field is blank — the "contact record is
    # accessible but empty" signal.
    def all_fields_blank?(field_map, sf_obj)
      field_map.keys.none? { |sf_field| sf_obj[sf_field].present? }
    end
  end

  private

  # Run one page of the application list query. A failure stops the run and
  # surfaces on the page: unlike per-record conditions, this means results
  # are incomplete. The banner shows the connector message; the full query
  # is already in the error log.
  #
  # @return [OpenStruct, false]
  def run_list_query(offset)
    result = connector.soql_query(unprocessed_soql(offset))
    @api_error = connector.error_message if result == false
    result
  end

  # Batched contact lookup for one page, keyed by the Ranger__c id. Runs
  # WITH USER_MODE, so an invisible contact is missing from the hash rather
  # than an error. A failed batch returns an empty hash — every record on
  # the page then reads as contact-inaccessible, deliberately without
  # setting api_error (ported behavior).
  #
  # @return [Hash{String => OpenStruct}]
  def query_contact_records(ids)
    return {} if ids.empty?

    result = connector.soql_query(contact_soql(ids))
    return {} if result == false

    result.records.index_by(&:Id)
  end

  def unprocessed_soql(offset)
    fields = (APPLICATION_FIELD_MAP.keys + APPLICATION_QUERY_ONLY_FIELDS).join(", ")
    types = APPLICANT_TYPES.map { |type| "Ranger_Applicant_Type__c=#{Salesforce.soql_quote(type)}" }.join(" OR ")

    # "View 1 - Check Qualifications" conditions.
    soql = "SELECT #{fields} FROM Ranger__c" \
           " WHERE (NOT VC_Approved_Radio_Call_Sign__c LIKE 'Testing%')" \
           " AND (VC_Status__c='Not Yet Started' OR VC_Status__c='In VC Intake Process')" \
           " AND (#{types})" \
           " AND VC_Qualifications_Check__c='Needs checking'" \
           " LIMIT #{PAGE_LIMIT}"
    soql += " OFFSET #{offset}" if offset.positive?
    soql
  end

  def contact_soql(ids)
    fields = (CONTACT_FIELD_MAP.keys + CONTACT_QUERY_ONLY_FIELDS).map { |field| "Ranger_Info__r.#{field}" }
    quoted = ids.map { |id| Salesforce.soql_quote(id) }.join(",")

    "SELECT Id, Ranger_Info__r.Id, #{fields.join(', ')} FROM Ranger__c" \
      " WHERE Id IN (#{quoted}) WITH USER_MODE LIMIT #{PAGE_LIMIT}"
  end

  # One page-scoped DB read instead of one lookup per record; Salesforce
  # names are auto-numbers and cannot repeat within a page.
  def existing_applications_by_name(records)
    ProspectiveApplication.where(year: Current.year, salesforce_name: records.map(&:Name))
                          .index_by(&:salesforce_name)
  end

  def import_application(sf_row, contact_row, existing_by_name, commit:)
    row = ProspectiveApplication.new
    self.class.extract_fields(APPLICATION_FIELD_MAP, sf_row, row)
    # The Salesforce event year is not used: applications are always
    # imported into the current event year (ported behavior).
    row.year = Current.year

    existing = existing_by_name[row.salesforce_name]
    if existing
      @existing_applications << existing
      return
    end

    ranger_info = contact_row && contact_row.Ranger_Info__r
    unless ranger_info
      add_failure(@query_failures, row, :contact_inaccessible)
      return
    end

    contact_id = ranger_info.Id
    self.class.extract_fields(CONTACT_FIELD_MAP, ranger_info, row)
    if self.class.all_fields_blank?(CONTACT_FIELD_MAP, ranger_info)
      add_failure(@query_failures, row, :contact_blank, contact_id:)
      return
    end

    if row.bpguid.blank? && row.person_id.present?
      row.bpguid = Person.where(id: row.person_id).pick(:bpguid).to_s
    end
    if row.bpguid.blank?
      add_failure(@query_failures, row, :missing_bpguid, contact_id:)
      return
    end

    sf_status = self.class.sanitize_field(sf_row, "VC_Status__c")
    row.status = self.class.status_for(sf_status, row.person_id)
    row.street = self.class.sanitize_street(row.street)
    row.phone = self.class.first_phone(ranger_info)
    row.emergency_contact = self.class.emergency_contact_from(ranger_info)
    row.experience = self.class.experience_for(self.class.sanitize_field(sf_row, "Attended_Burning_Man_Twice__c"))
    row.is_over_18 = self.class.sanitize_field(sf_row, "Ranger_Info_Over_18_Check__c") == "Yes"
    row.approved_handle = "" if self.class.recycled_handle?(row.approved_handle)
    if row.status == ProspectiveApplication::STATUS_CREATED
      row.why_volunteer_review = ProspectiveApplication::WHY_VOLUNTEER_REVIEW_OKAY
    end

    if commit
      commit_application(row, sf_row, sf_status, contact_id)
    else
      @new_applications << row
    end
  end

  # Save one application plus its audit log entry and imported notes, all or
  # nothing. Validation failures and exceptions land in create_failures and
  # the run moves on to the next record.
  def commit_application(row, sf_row, sf_status, contact_id)
    ProspectiveApplication.transaction do
      unless row.save
        message = "Fields failed to validate:\n" +
                  row.errors.map { |error| "#{error.attribute}: #{error.message}" }.join("\n")
        add_failure(@create_failures, row, :invalid, message, contact_id:)
        # Validation messages carry no field values, so this log is safe;
        # the full row is deliberately NOT logged (error_log is broadly
        # readable, the application fields are PII).
        ErrorLog.record("prospective-application-validation-failure",
                        data: { record: identifying_fields(row), errors: row.errors.to_hash })
        raise ActiveRecord::Rollback
      end

      ProspectiveApplicationLog.record(row.id, ProspectiveApplicationLog::ACTION_IMPORTED,
                                       { salesforce_status: sf_status,
                                         salesforce_type: self.class.sanitize_field(sf_row, "Ranger_Applicant_Type__c") })

      insert_note(row, ProspectiveApplicationNote::TYPE_VC,
                  self.class.sanitize_field(sf_row, "VC_Comments__c"))
      insert_note(row, ProspectiveApplicationNote::TYPE_VC_COMMENT,
                  self.class.sanitize_field(sf_row, "Why_Ranger_Comments__c"))

      @new_applications << row
    end
  rescue StandardError => e
    # The transaction has rolled back; nothing for this record was kept.
    add_failure(@create_failures, row, :create_failure, e.message, contact_id:)

    # The exception message can embed INSERT values, so only the class and
    # source location are logged; the message itself stays on the page for
    # the operator, who already owns this record's PII.
    file, line = e.backtrace&.first&.split(":")
    ErrorLog.record("prospective-application-create-failure", data: {
      record: identifying_fields(row).merge(api_error: "create-failure"),
      exception: { class: e.class.name, file: file, line: line }
    })
  end

  # A nil person authors the note; the notes list renders that as
  # "imported from Salesforce". Passing the record (not the id) spares the
  # belongs_to presence validation a redundant parent SELECT.
  def insert_note(application, type, note)
    return if note.blank?

    ProspectiveApplicationNote.create!(prospective_application: application, type: type, note: note)
  end

  def add_failure(bucket, row, error, message = nil, contact_id: nil)
    bucket << Failure.new(application: row, error: error, message: message, contact_id: contact_id)
  end

  def identifying_fields(row)
    { salesforce_id: row.salesforce_id, salesforce_name: row.salesforce_name }
  end
end
