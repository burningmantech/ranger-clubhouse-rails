# frozen_string_literal: true

class AccessDocument < ApplicationRecord
  self.table_name = "access_document"
  self.inheritance_column = "none"
  self.audit_model = true

  # Statuses
  BANKED = "banked"
  CANCELLED = "cancelled"
  CLAIMED = "claimed"
  EXPIRED = "expired"
  QUALIFIED = "qualified"
  SUBMITTED = "submitted"
  TURNED_DOWN = "turned_down"
  USED = "used"

  ACTIVE_STATUSES = [QUALIFIED, CLAIMED, BANKED].freeze
  # Document is live/available this event -- unlike CURRENT_STATUSES, banked doesn't count.
  AVAILABLE_STATUSES = [QUALIFIED, CLAIMED, SUBMITTED].freeze
  CURRENT_STATUSES = [QUALIFIED, CLAIMED, BANKED, SUBMITTED].freeze
  INVALID_STATUSES = [USED, CANCELLED, EXPIRED].freeze

  # Access Document types
  GIFT = "gift_ticket"
  LSD = "lsd_ticket"
  SPT = "special_price_ticket" # fka Reduced-Price Ticket (RPT)
  STAFF_CREDENTIAL = "staff_credential"
  VEHICLE_PASS_SP = "vehicle_pass_sp"
  VEHICLE_PASS_GIFT = "vehicle_pass_gift"
  VEHICLE_PASS_LSD = "vehicle_pass_lsd"
  SAP = "work_access_pass" # value retains legacy "work_access_pass" spelling to avoid a DB migration
  SAPSO = "work_access_pass_so" # value retains legacy "work_access_pass_so" spelling to avoid a DB migration

  TICKET_TYPES = [GIFT, LSD, SPT, STAFF_CREDENTIAL].freeze
  REGULAR_TICKET_TYPES = [SPT, STAFF_CREDENTIAL].freeze
  SPECIAL_TICKET_TYPES = [GIFT, LSD].freeze
  SPECIAL_VP_TYPES = [VEHICLE_PASS_LSD].freeze

  DELIVERABLE_TYPES = [
    GIFT, LSD, SPT, STAFF_CREDENTIAL, VEHICLE_PASS_GIFT, VEHICLE_PASS_SP
  ].freeze

  HAS_ACCESS_DATE_TYPES = [STAFF_CREDENTIAL, SAP, SAPSO].freeze

  EXPIRE_THIS_YEAR_TYPES = [
    GIFT, LSD, VEHICLE_PASS_SP, VEHICLE_PASS_GIFT, VEHICLE_PASS_LSD, SAP, SAPSO
  ].freeze

  TYPE_LABELS = {
    GIFT => "Gift Ticket",
    LSD => "LSD Ticket",
    SPT => "Special Price Ticket",
    STAFF_CREDENTIAL => "Staff Credential",
    VEHICLE_PASS_SP => "Vehicle Pass (Special Price)",
    VEHICLE_PASS_GIFT => "Vehicle Pass (Gift)",
    VEHICLE_PASS_LSD => "Vehicle Pass (LSD)",
    SAP => "SAP",
    SAPSO => "SO SAP"
  }.freeze

  SHORT_TICKET_LABELS = {
    GIFT => "GIFT",
    LSD => "LSD",
    SPT => "SPT",
    STAFF_CREDENTIAL => "SC",
    VEHICLE_PASS_SP => "VPSP",
    VEHICLE_PASS_GIFT => "VPGIFT",
    VEHICLE_PASS_LSD => "VPLSD",
    SAP => "SAP",
    SAPSO => "SO SAP"
  }.freeze

  # Delivery methods
  DELIVERY_NONE = "none"
  DELIVERY_POSTAL = "postal"
  DELIVERY_EMAIL = "email"
  DELIVERY_WILL_CALL = "will_call"
  DELIVERY_PRIORITY = "priority"

  DELIVERY_LABELS = {
    DELIVERY_NONE => "None",
    DELIVERY_POSTAL => "USPS Standard Mail",
    DELIVERY_EMAIL => "Email",
    DELIVERY_WILL_CALL => "Will Call",
    DELIVERY_PRIORITY => "USPS Priority Mail"
  }.freeze

  # Associations
  belongs_to :person
  has_many :access_document_changes, foreign_key: :record_id, dependent: :delete_all

  attr_writer :has_staff_credential

  # Virtual attribute for appending comments
  attribute :additional_comments, :string

  # Callbacks
  before_save :set_created_at_if_blank
  before_save :set_expiry_date_for_expire_this_year
  before_save :set_delivery_method_by_type
  before_save :clear_name_for_non_name_types
  before_save :clear_access_date_for_non_access_date_types
  before_save :prepend_additional_comments

  # Per-document change log (access_document_changes table), in addition to the
  # generic ActionLog audit from ApplicationRecord. Matches the Laravel behavior.
  after_create :log_change_create
  after_update :log_change_modify
  after_destroy :log_change_delete

  # Scopes
  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :current, -> { where(status: CURRENT_STATUSES) }
  scope :valid, -> { where.not(status: INVALID_STATUSES) }

  # Normalize blank address fields to empty strings
  normalizes :street1, :street2, :city, :state, :postal_code, :country, with: ->(value) { value.presence || "" }

  # Normalize access_date to nil if empty
  normalizes :access_date, with: ->(value) { value.presence }

  class << self
    # Find records matching given criteria.
    #
    # Query parameters:
    #   status: 'all' for all documents, or specific status(es)
    #   person_id: find for a specific person
    #   year: for a specific source_year
    #   type: specific document type(s)
    #   include_person: include person association
    #
    def find_for_query(query)
      scope = order(:type)

      status = query[:status]
      person_id = query[:person_id]
      year = query[:year]
      type = query[:type]
      include_person = query[:include_person]

      if status != "all"
        scope = if status.blank?
          scope.where.not(status: INVALID_STATUSES)
                else
          statuses = status.is_a?(String) ? status.split(",") : status
          scope.where(status: statuses)
                end
      end

      scope = scope.where(person_id: person_id) if person_id.present?

      if type.present?
        types = type.split(",") if type.is_a?(String)
        scope = scope.where(type: types)
      end

      scope = scope.where(source_year: year) if year.present?

      if include_person
        scope = scope.includes(:person)
        scope.sort_by { |row| row.person&.callsign&.downcase || "" }
      else
        scope.order(:source_year)
      end
    end

    # Check if no available tickets exist -- must have an unbanked ticket.
    def no_available_tickets?(person_id)
      where(person_id: person_id)
        .where(type: REGULAR_TICKET_TYPES)
        .where(status: AVAILABLE_STATUSES)
        .none?
    end

    # Did the person claim a ticket or a SAP?
    def claimed_ticket_or_sap?(person_id)
      where(person_id: person_id)
        .where(type: [*REGULAR_TICKET_TYPES, SAP])
        .where(status: [CLAIMED, SUBMITTED])
        .exists?
    end

    # Find all available (qualified, claimed, banked) deliverables for a person
    def find_all_available_deliverables_for_person(person_id)
      where(person_id: person_id)
        .where(type: DELIVERABLE_TYPES)
        .where(status: [QUALIFIED, CLAIMED, BANKED])
    end

    # Find a candidate SAP for a person
    def find_sap_for_person(person_id)
      rows = where(person_id: person_id)
        .where(type: [STAFF_CREDENTIAL, SAP])
        .where(status: [QUALIFIED, CLAIMED, BANKED, SUBMITTED])
        .order(:source_year)

      claimed_or_submitted = rows.select { |row| [CLAIMED, SUBMITTED].include?(row.status) }
      sap_candidate(claimed_or_submitted) || sap_candidate(rows)
    end

    # Find the SAP for multiple people
    def find_sap_for_person_ids(person_ids)
      saps = where(person_id: person_ids)
        .where(type: [STAFF_CREDENTIAL, SAP])
        .where(status: [QUALIFIED, CLAIMED, BANKED, SUBMITTED])
        .order(:source_year)
        .group_by(&:person_id)

      saps.transform_values do |rows|
        claimed_or_submitted = rows.select { |row| [CLAIMED, SUBMITTED].include?(row.status) }
        sap_candidate(claimed_or_submitted) || sap_candidate(rows)
      end
    end

    # Retrieve everyone who has a SAP prior to the given date.
    def retrieve_saps_prior_to(prior_to)
      saps = where(type: [STAFF_CREDENTIAL, SAP])
        .where(status: AVAILABLE_STATUSES)
        .where("(access_date IS NOT NULL AND access_date < ?) OR access_any_time = true", prior_to)
        .includes(:person)
        .order(:source_year)
        .group_by(&:person_id)

      saps.values.map { |rows| sap_candidate(rows) }
    end

    # Find the most appropriate SAP candidate record.
    # The first record with any time access takes priority,
    # followed by the earliest access date.
    def sap_candidate(rows)
      return nil if rows.blank?

      rows.each do |row|
        return row if row.access_any_time
      end

      rows.min_by { |row| row.access_date || Date.new(9999, 12, 31) }
    end

    # Update all non-submitted SAP & Staff Credentials with new access date
    def update_saps_for_person(person_id, access_date, access_any_time, reason)
      access_date = access_date.presence

      where(person_id: person_id)
        .where(type: [STAFF_CREDENTIAL, SAP])
        .where(status: [QUALIFIED, CLAIMED, BANKED])
        .find_each do |row|
          row.access_date = access_date
          row.access_any_time = access_any_time
          row.audit_reason = reason
          row.save(validate: false)
        end
    end

    # Find all the Significant Other SAPs for a person
    def find_so_saps_for_person(person_id)
      where(type: SAPSO)
        .where(person_id: person_id)
        .where.not(status: INVALID_STATUSES)
    end

    # Count how many (current) Significant Other SAPs for a person
    def so_sap_count(person_id)
      where(person_id: person_id)
        .where(type: SAPSO)
        .where.not(status: INVALID_STATUSES)
        .count
    end

    # Find a record belonging to a person.
    def find_for_person(person_id, id)
      where(person_id: person_id).find(id)
    end

    # Create a Significant Others Work Access Pass and claim it.
    def create_so_sap(person_id, year, name)
      create!(
        person_id: person_id,
        name: name,
        type: SAPSO,
        status: CLAIMED,
        access_date: Setting.get_value(Setting::TAS_DEFAULT_SOSAP_DATE),
        source_year: year,
        expiry_date: year
      )
    end
  end

  # Add a comment to the comments column.
  def add_comment(comment, user)
    callsign = user.is_a?(Person) ? user.callsign : user
    timestamp = Current.time.strftime("%-m/%-d/%y %-H:%M:%S")
    self.comments = "#{timestamp} #{callsign}: #{comment}\n#{comments}"
  end

  # Virtual attribute combining access_date and access_any_time into the single
  # admin-form choice: ADMISSION_ANY, an ISO date, or blank (unspecified).
  ADMISSION_ANY = "any"

  def admission_date
    return ADMISSION_ANY if access_any_time

    access_date&.to_date&.iso8601
  end

  def admission_date=(value)
    if value == ADMISSION_ANY
      self.access_any_time = true
      self.access_date = nil
    else
      self.access_any_time = false
      self.access_date = value.presence
    end
  end

  # Setter for expiry_date. Fix the date if it's only a year.
  def expiry_date=(value)
    if value.present?
      value = value.to_s
      value = "#{value}-09-15" if value.length == 4
    end
    super
  end

  # Return true if the document expired
  def past_expire_date?
    expiry_date.present? && expiry_date.year < Current.time.year
  end

  # Return true if the person claimed a SC for the year
  def has_staff_credential?
    @has_staff_credential || false
  end

  # Is this a SPT or SC ticket?
  def regular_ticket?
    REGULAR_TICKET_TYPES.include?(type)
  end

  # Is this a special ticket (Gift or LSD)?
  def special_ticket?
    SPECIAL_TICKET_TYPES.include?(type)
  end

  # Is this a special Ticket or VP?
  def special_document?
    special_ticket? || special_vp?
  end

  # Is this a Special Vehicle Pass?
  def special_vp?
    SPECIAL_VP_TYPES.include?(type)
  end

  # Is the document available (qualified, claimed, or submitted)?
  def available?
    AVAILABLE_STATUSES.include?(status)
  end

  def is_using?
    [CLAIMED, SUBMITTED].include?(status)
  end

  def is_banked?
    status == BANKED
  end

  def is_qualified?
    status == QUALIFIED
  end

  # Get the human-readable type label
  def type_label
    TYPE_LABELS[type] || type
  end

  # Get the human-readable delivery method label
  def delivery_method_label
    DELIVERY_LABELS[delivery_method] || delivery_method
  end

  # Display reference shown to admins and ticketing staff (e.g. "RAD-1234")
  def display_ref
    "RAD-#{id}"
  end

  # Get the short type label
  def short_type_label
    SHORT_TICKET_LABELS[type] || type
  end

  # Does the document have all the necessary address fields?
  def has_address?
    %w[street1 city state postal_code].all? { |field| send(field).present? }
  end

  # Does this access document type expire after the event?
  def expire_this_year?
    EXPIRE_THIS_YEAR_TYPES.include?(type)
  end

  def delivery_none?
    delivery_method == DELIVERY_NONE
  end

  def delivery_will_call?
    delivery_method == DELIVERY_WILL_CALL
  end

  def delivery_postal?
    delivery_method == DELIVERY_POSTAL
  end

  def delivery_priority?
    delivery_method == DELIVERY_PRIORITY
  end

  def staff_credential?
    type == STAFF_CREDENTIAL
  end

  def vehicle_pass_sp?
    type == VEHICLE_PASS_SP
  end

  def using_vehicle_pass?
    (type == VEHICLE_PASS_SP || type == VEHICLE_PASS_GIFT) && (status == CLAIMED || status == SUBMITTED)
  end

  private

  def set_created_at_if_blank
    self.created_at ||= Current.time
  end

  def set_expiry_date_for_expire_this_year
    return unless expire_this_year?

    year = Current.year
    if expiry_date.blank? || expiry_date.year > year
      self.expiry_date = year
    end
  end

  def set_delivery_method_by_type
    case type
    when SPT
      if status_changed? && [BANKED, QUALIFIED].include?(status)
        self.delivery_method = DELIVERY_NONE
      end
    when SAP, SAPSO
      self.delivery_method = DELIVERY_EMAIL
    when STAFF_CREDENTIAL
      self.delivery_method = DELIVERY_WILL_CALL
    when GIFT, VEHICLE_PASS_GIFT
      self.delivery_method = DELIVERY_NONE if status == QUALIFIED
    when LSD, VEHICLE_PASS_LSD
      # LSD items are uploaded to the Clubhouse AFTER the recipient has stated they want the goodies.
      # End-users are only told about the items and not given an opportunity to decline.
      self.status = CLAIMED if status == QUALIFIED
    end
  end

  def clear_name_for_non_name_types
    # Only Gift, LSD, and SAP SOs can have names
    self.name = nil unless [SAPSO, LSD, GIFT].include?(type)
  end

  def clear_access_date_for_non_access_date_types
    # Only SCs and SAPs have access dates
    return if HAS_ACCESS_DATE_TYPES.include?(type)

    self.access_date = nil
    self.access_any_time = false
  end

  def prepend_additional_comments
    return if additional_comments.blank?

    timestamp = Current.time.strftime("%-m/%-d/%y %-H:%M:%S")
    callsign = Current.person&.callsign || "(unknown)"
    self.comments = "#{timestamp} #{callsign}: #{additional_comments}\n#{comments}"
  end

  def log_change_create
    AccessDocumentChange.log(self, Current.person_id, persisted_audit_attributes, AccessDocumentChange::OP_CREATE)
  end

  def log_change_modify
    AccessDocumentChange.log(self, Current.person_id,
                             changed_values.except("created_at", "updated_at"),
                             AccessDocumentChange::OP_MODIFY)
  end

  def log_change_delete
    AccessDocumentChange.log(self, Current.person_id, persisted_audit_attributes, AccessDocumentChange::OP_DELETE)
  end
end
