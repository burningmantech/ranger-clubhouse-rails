# frozen_string_literal: true

class ProspectiveApplication < ApplicationRecord
  self.table_name = "prospective_application"
  self.audit_model = true
  self.audit_exclude = %w[created_at updated_at updated_by_person_id updated_by_person_at].freeze

  STATUS_PENDING = "pending"
  STATUS_APPROVED = "approved"
  STATUS_CREATED = "created"
  STATUS_MORE_HANDLES = "more-handles"
  STATUS_HANDLE_CHECK = "handle-check"

  STATUS_HOLD_AGE_ISSUE = "age-issue"
  STATUS_HOLD_PII_ISSUE = "pii-issue"
  STATUS_HOLD_QUALIFICATION_ISSUE = "qualification-issue"
  STATUS_HOLD_RRN_CHECK = "rrn-check"
  STATUS_HOLD_WHY_RANGER_QUESTION = "why-ranger-question"

  STATUS_REJECT_PRE_BONK = "reject-pre-bonk"
  STATUS_REJECT_UBERBONKED = "reject-uber-bonked"
  STATUS_REJECT_TOO_YOUNG = "reject-too-young"
  STATUS_REJECT_UNQUALIFIED = "reject-unqualified"
  STATUS_REJECT_REGIONAL = "reject-regional"
  STATUS_REJECT_RETURNING_RANGER = "reject-returning-ranger"
  STATUS_DUPLICATE = "duplicate"

  STOP_STATUSES = [
    STATUS_REJECT_PRE_BONK,
    STATUS_REJECT_UBERBONKED,
    STATUS_REJECT_TOO_YOUNG,
    STATUS_REJECT_UNQUALIFIED,
    STATUS_REJECT_REGIONAL,
    STATUS_REJECT_RETURNING_RANGER,
    STATUS_DUPLICATE
  ].freeze

  HELD_STATUSES = [
    STATUS_MORE_HANDLES,
    STATUS_HOLD_AGE_ISSUE,
    STATUS_HOLD_PII_ISSUE,
    STATUS_HOLD_QUALIFICATION_ISSUE,
    STATUS_HOLD_RRN_CHECK,
    STATUS_HOLD_WHY_RANGER_QUESTION
  ].freeze

  ALL_STATUSES = [
    STATUS_PENDING,
    STATUS_HANDLE_CHECK,
    STATUS_APPROVED,
    STATUS_CREATED,
    *HELD_STATUSES,
    *STOP_STATUSES
  ].freeze

  STATUS_LABELS = {
    STATUS_APPROVED => "Awaiting Account Creation",
    STATUS_CREATED => "Account Created",
    STATUS_DUPLICATE => "Duplicate",
    STATUS_HANDLE_CHECK => "Callsign Processing",
    STATUS_HOLD_AGE_ISSUE => "Age Confirmation",
    STATUS_MORE_HANDLES => "More Handles",
    STATUS_HOLD_QUALIFICATION_ISSUE => "Event Confirmation",
    STATUS_HOLD_RRN_CHECK => "RRN Verification",
    STATUS_HOLD_WHY_RANGER_QUESTION => "Answer Issue",
    STATUS_PENDING => "Awaiting Review",
    STATUS_HOLD_PII_ISSUE => "PII Issue",
    STATUS_REJECT_PRE_BONK => "Pre-Bonked",
    STATUS_REJECT_REGIONAL => "Failed RRN",
    STATUS_REJECT_RETURNING_RANGER => "Returning Ranger",
    STATUS_REJECT_TOO_YOUNG => "Too Young",
    STATUS_REJECT_UBERBONKED => "Uberbonked",
    STATUS_REJECT_UNQUALIFIED => "Lacking Events"
  }.freeze

  # Grouped options for status selects, in workflow order.
  STATUS_OPTIONS = [
    ["Regular Workflow", [
      ["Awaiting Review", STATUS_PENDING],
      ["In Callsign Processing", STATUS_HANDLE_CHECK],
      ["Awaiting Account Creation", STATUS_APPROVED],
      ["Account Created", STATUS_CREATED]
    ]],
    ["On Hold", [
      ["More Handles Requested", STATUS_MORE_HANDLES],
      ["Personal Info Issue", STATUS_HOLD_PII_ISSUE],
      ["Awaiting Event Confirmation", STATUS_HOLD_QUALIFICATION_ISSUE],
      ["Awaiting Age Confirmation", STATUS_HOLD_AGE_ISSUE],
      ["Awaiting RRN Verification", STATUS_HOLD_RRN_CHECK],
      ["Why Ranger Answer Issue", STATUS_HOLD_WHY_RANGER_QUESTION]
    ]],
    ["Rejected", [
      ["Duplicate Application", STATUS_DUPLICATE],
      ["Failed RRN Verification", STATUS_REJECT_REGIONAL],
      ["Lacking Event Experience", STATUS_REJECT_UNQUALIFIED],
      ["Pre-Bonked", STATUS_REJECT_PRE_BONK],
      ["Returning Ranger", STATUS_REJECT_RETURNING_RANGER],
      ["Too Young", STATUS_REJECT_TOO_YOUNG],
      ["Uberbonked", STATUS_REJECT_UBERBONKED]
    ]]
  ].freeze

  # DaisyUI badge colors per status.
  STATUS_COLORS = {
    STATUS_APPROVED => "success",
    STATUS_CREATED => "success",
    STATUS_DUPLICATE => "error",
    STATUS_HANDLE_CHECK => "neutral",
    STATUS_HOLD_AGE_ISSUE => "warning",
    STATUS_MORE_HANDLES => "warning",
    STATUS_HOLD_QUALIFICATION_ISSUE => "warning",
    STATUS_HOLD_RRN_CHECK => "warning",
    STATUS_HOLD_WHY_RANGER_QUESTION => "warning",
    STATUS_PENDING => "info",
    STATUS_HOLD_PII_ISSUE => "warning",
    STATUS_REJECT_PRE_BONK => "error",
    STATUS_REJECT_REGIONAL => "error",
    STATUS_REJECT_RETURNING_RANGER => "error",
    STATUS_REJECT_TOO_YOUNG => "error",
    STATUS_REJECT_UBERBONKED => "error",
    STATUS_REJECT_UNQUALIFIED => "error"
  }.freeze

  STATUSES_THAT_SEND_EMAIL = [
    STATUS_APPROVED,
    STATUS_HOLD_AGE_ISSUE,
    STATUS_HOLD_QUALIFICATION_ISSUE,
    STATUS_HOLD_RRN_CHECK,
    STATUS_HOLD_WHY_RANGER_QUESTION,
    STATUS_MORE_HANDLES,
    STATUS_HOLD_PII_ISSUE,
    STATUS_REJECT_REGIONAL,
    STATUS_REJECT_RETURNING_RANGER,
    STATUS_REJECT_TOO_YOUNG,
    STATUS_REJECT_UNQUALIFIED
  ].freeze

  EXPERIENCE_BRC1 = "brc1"
  EXPERIENCE_BRC1R1 = "brc1r1"
  EXPERIENCE_BRC2 = "brc2"
  EXPERIENCE_NONE = "none"

  EXPERIENCE_LABELS = {
    EXPERIENCE_NONE => "None",
    EXPERIENCE_BRC1 => "BRC1",
    EXPERIENCE_BRC1R1 => "BRC1 + R1",
    EXPERIENCE_BRC2 => "BRC2"
  }.freeze

  WHY_VOLUNTEER_REVIEW_OKAY = "okay"
  WHY_VOLUNTEER_REVIEW_PROBLEM = "problem"
  WHY_VOLUNTEER_REVIEW_UNREVIEWED = "unreviewed"

  WHY_VOLUNTEER_REVIEW_LABELS = {
    WHY_VOLUNTEER_REVIEW_OKAY => "Okay",
    WHY_VOLUNTEER_REVIEW_PROBLEM => "Problem",
    WHY_VOLUNTEER_REVIEW_UNREVIEWED => "Unreviewed"
  }.freeze

  # Column labels for the audit log display. Salesforce columns are pseudo
  # columns that only appear in imported audit records.
  COLUMN_LABELS = {
    "status" => "Status",
    "events_attended" => "Events Attended",
    "first_name" => "First Name",
    "last_name" => "Last Name",
    "year" => "Event Year",
    "email" => "Email",
    "bpguid" => "BPGUID",
    "is_over_18" => "Is Over 18?",
    "why_volunteer" => "Why Ranger?",
    "why_volunteer_review" => "Why Ranger Review",
    "reviewed_at" => "Reviewed At",
    "known_rangers" => "Known Rangers",
    "known_applicants" => "Known Applicants",
    "handles" => "Handles",
    "approved_handle" => "Approved Handle",
    "regional_experience" => "Regional Experience",
    "regional_callsign" => "Regional Callsign",
    "experience" => "Experience",
    "street" => "Street",
    "city" => "City",
    "state" => "State",
    "postal_code" => "Postal Code",
    "country" => "Country",
    "phone" => "Phone",
    "emergency_contact" => "Emergency Contact",
    "assigned_person_id" => "Assigned Person",
    "salesforce_status" => "Salesforce Status",
    "salesforce_type" => "Application Type"
  }.freeze

  # How many events back an attended event still qualifies.
  QUALIFIED_ATTENDANCE_WINDOW = 10

  HANDLE_ISSUE_REGEXPS = [
    [/\branger\b/i, 'The word "Ranger" detected - remove the word.'],
    [/[,"!()]/, "Punctuation (commas, periods, double quote, exclamations, parentheses) detected - remove all punctuations. Dashes are okay IF its part of the actual handle"]
  ].freeze

  # Statuses of existing accounts a submitted handle may conflict with.
  HANDLE_CONFLICT_STATUSES = [
    Person::ACTIVE, Person::INACTIVE, Person::INACTIVE_EXTENSION, Person::PROSPECTIVE, Person::ALPHA
  ].freeze

  # The account created from this approved application.
  belongs_to :person, optional: true
  # Account potentially associated with the applicant. Used to detect
  # returning Rangers or past prospectives who applied again.
  has_one :bpguid_person, class_name: "Person", primary_key: :bpguid, foreign_key: :bpguid
  belongs_to :assigned_person, class_name: "Person", optional: true
  belongs_to :review_person, class_name: "Person", optional: true
  belongs_to :updated_by_person, class_name: "Person", optional: true

  has_many :notes, class_name: "ProspectiveApplicationNote", dependent: :delete_all
  has_many :audit_logs, class_name: "ProspectiveApplicationLog", dependent: :delete_all
  has_many :mail_logs, -> { order(:created_at) }

  BASIC_INCLUDES = [:person, :bpguid_person, :assigned_person, :updated_by_person, :review_person].freeze
  FULL_INCLUDES = (BASIC_INCLUDES + [{ notes: :person }, { audit_logs: :person }, { mail_logs: :sender }]).freeze

  serialize :rejected_handles, coder: JSON
  serialize :problem_handles, coder: JSON

  # Set by #screen_handles for display; not persisted.
  attr_reader :screened_handles

  validates :bpguid, :email, :year, presence: true
  validates :status, inclusion: { in: ALL_STATUSES }

  # Enforced only when a VC edits the personal-info section; imported
  # applications legitimately arrive with blank fields (the PII-issue flow).
  with_options on: :personal_info do
    validates :first_name, :last_name, :street, :city, :postal_code, :country, presence: true
    validates :phone, presence: true, length: { minimum: 9 }
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: Person::EMAIL_MESSAGE }
    # On every save, not only a change: the address exists to become the
    # account's, and Create Prospectives would refuse it there.
    validate :email_is_sendable
    validate :state_required_for_country
  end

  before_update :stamp_updated_by
  after_update :record_update_log

  class << self
    def find_by_application_id!(application_id)
      find(application_id.to_s.sub(/\A[Aa]-/, ""))
    end

    # Applications approved for this year and awaiting account creation.
    def retrieve_approved
      where(status: STATUS_APPROVED, year: Current.year).order(:id)
    end

    def find_for_query(year: nil, status: nil, contact: nil, person_id: nil)
      sql = includes(BASIC_INCLUDES)
      sql = sql.where(year:) if year.present?
      sql = sql.where(status:) if status.present?
      sql = sql.where(person_id:) if person_id.present?

      if contact.present?
        sql = if contact.include?("@")
                sql.where(email: contact)
              else
                sql.where("CONCAT(first_name, ' ', last_name) LIKE ?", "%#{sanitize_sql_like(contact)}%")
              end
      end

      sql.order(contact.present? ? :last_name : :id)
    end

    # Search by application id (A-NNN), Salesforce id (R-NNNN), email,
    # BPGUID, or name.
    def search_for_applications(query)
      case query
      when /\A[Aa]-/
        where(id: query.sub(/\A[Aa]-/, "")).to_a
      when /\A[Rr]-/
        where(salesforce_name: query).order(year: :desc).to_a
      when /@/
        where(email: query).order(year: :desc).to_a
      when /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i
        where(bpguid: query).order(year: :desc).to_a
      else
        where("CONCAT(first_name, ' ', last_name) LIKE ?", "%#{sanitize_sql_like(query)}%")
          .order(year: :desc, last_name: :asc)
          .to_a
      end
    end
  end

  def application_id
    "A-#{id}"
  end

  def related_applications
    self.class.where(bpguid:).where.not(id:).order(:year)
  end

  # -- Event attendance --------------------------------------------------

  def events_attended
    value = super
    value == "None" ? "" : value
  end

  def events_attended=(value)
    super(value == "None" ? "" : value.to_s)
  end

  def all_events
    events_attended.blank? ? [] : events_attended.split(";").map(&:to_i)
  end

  # Non-pandemic events used for review display & qualification checks.
  def non_pandemic_events
    all_events - EventYearSpan::PANDEMIC_YEARS
  end

  # Events recent enough to qualify (used by the rejection email).
  def qualified_events
    cutoff = Current.year - (QUALIFIED_ATTENDANCE_WINDOW + 1)
    non_pandemic_events.select { |year| year >= cutoff }
  end

  # Events too old to qualify (used by the rejection email).
  def old_events
    cutoff = Current.year - QUALIFIED_ATTENDANCE_WINDOW
    all_events.select { |year| year < cutoff }
  end

  def have_pandemic_years?
    all_events.intersect?(EventYearSpan::PANDEMIC_YEARS)
  end

  # Attended one of the last QUALIFIED_ATTENDANCE_WINDOW events before this
  # year's. Events, not years: 2020 and 2021 had none, so they use up no part
  # of the window.
  def qualified_event_year?
    cutoff = EventYearSpan.last_years(QUALIFIED_ATTENDANCE_WINDOW, through: Current.year - 1).first
    non_pandemic_events.any? { |year| year >= cutoff }
  end

  def brc_experience_okay?
    non_pandemic_events.any? && qualified_event_year?
  end

  def experience_issue
    if non_pandemic_events.empty?
      "NO QUALIFIED EVENT YEARS LISTED"
    elsif !qualified_event_year?
      "No qualifying event within the last #{QUALIFIED_ATTENDANCE_WINDOW} events (not years)"
    end
  end

  # -- Status ------------------------------------------------------------

  def status_label
    STATUS_LABELS[status] || "Bug [#{status}]"
  end

  def status_color
    STATUS_COLORS[status] || "neutral"
  end

  def stop_status?
    STOP_STATUSES.include?(status)
  end

  def held_status?
    HELD_STATUSES.include?(status)
  end

  def processing_callsign?
    status == STATUS_HANDLE_CHECK || status == STATUS_MORE_HANDLES
  end

  def bonked?
    status == STATUS_REJECT_PRE_BONK || status == STATUS_REJECT_UBERBONKED
  end

  def status_pending? = status == STATUS_PENDING
  def status_approved? = status == STATUS_APPROVED
  def status_created? = status == STATUS_CREATED
  def status_duplicate? = status == STATUS_DUPLICATE
  def status_handle_check? = status == STATUS_HANDLE_CHECK
  def status_more_handles? = status == STATUS_MORE_HANDLES
  def status_hold_pii_issue? = status == STATUS_HOLD_PII_ISSUE
  def status_hold_qualification_issue? = status == STATUS_HOLD_QUALIFICATION_ISSUE
  def status_hold_age_issue? = status == STATUS_HOLD_AGE_ISSUE
  def status_hold_rrn_check? = status == STATUS_HOLD_RRN_CHECK
  def status_hold_why_ranger_question? = status == STATUS_HOLD_WHY_RANGER_QUESTION

  # Rejected, marked duplicate, or the account exists — decision actions are closed.
  def finalized? = stop_status? || status_created?

  # Nothing left to review: finalized, or approved and awaiting account creation.
  def decided? = finalized? || status_approved?

  # -- Associated accounts -------------------------------------------------

  def existing_account
    person || bpguid_person
  end

  def returning_applicant?
    existing_account&.status == Person::PAST_PROSPECTIVE
  end

  def uberbonked_previously?
    existing_account&.status == Person::UBERBONKED
  end

  def returning_ranger?
    [Person::ACTIVE, Person::INACTIVE, Person::INACTIVE_EXTENSION, Person::RETIRED].include?(existing_account&.status)
  end

  # -- Reviews -------------------------------------------------------------

  def experience_label
    EXPERIENCE_LABELS[experience] || "Bug: Unknown Experience [#{experience}]"
  end

  def experience_none?
    experience == EXPERIENCE_NONE
  end

  def why_volunteer_review_label
    WHY_VOLUNTEER_REVIEW_LABELS[why_volunteer_review] || "Bug [#{why_volunteer_review}]"
  end

  # -- Personal info -------------------------------------------------------

  # Countries where a blank state/province is considered an issue.
  COUNTRIES_WITH_STATES = %w[US CA AU].freeze

  # Which PII fields are blank. Support function for the PII issue email.
  def blank_personal_info
    fields = []
    fields << "Street Address" if street.blank?
    fields << "City" if city.blank?

    if country.blank?
      fields << "Country"
    elsif COUNTRIES_WITH_STATES.include?(country) && state.blank?
      fields << (country == "US" ? "State" : "Province")
    end

    fields << "Zip / Postal Code" if postal_code.blank?
    fields << "Telephone number" if phone.blank?
    fields
  end

  def personal_info_issues?
    %w[street city postal_code country phone].any? { |field| self[field].blank? } ||
      (COUNTRIES_WITH_STATES.include?(country) && state.blank?)
  end

  # -- Handles ---------------------------------------------------------------

  def handles=(value)
    if value.blank?
      super("")
    else
      lines = value.gsub("\r\n", "\n").delete("\r").split("\n")
      super(lines.reject { |line| line.strip.empty? }.join("\n"))
    end
  end

  def handle_list
    handles.blank? ? [] : handles.split("\n")
  end

  def handle_list_issues
    HANDLE_ISSUE_REGEXPS.filter_map { |regexp, issue| issue if handles.match?(regexp) }
  end

  # Move the current handle submissions onto the rejection history.
  def record_rejections(message)
    return if handle_list.empty?

    rejection = {
      "rejected_at" => Time.zone.now.to_s,
      "handles" => handle_list,
      "message" => message,
      "rejected_by_id" => Current.person_id
    }

    self.rejected_handles = [rejection, *rejected_handles]
    self.handles = ""
  end

  # Check each submitted handle against handle reservations and existing
  # accounts. Results land in #screened_handles for display.
  def screen_handles
    normalized_handles = handle_list.index_with { |handle| WordUtils.normalize_word(handle) }

    people = Person
               .where(callsign_normalized: normalized_handles.values)
               .where(status: HANDLE_CONFLICT_STATUSES).or(
                 Person.where(callsign_normalized: normalized_handles.values, vintage: true))
               .select(:id, :callsign, :status, :bpguid, :callsign_normalized)
               .index_by(&:callsign_normalized)
    reservations = HandleReservation
                     .active
                     .where(normalized_handle: normalized_handles.values)
                     .order(:handle)
                     .group_by(&:normalized_handle)

    @screened_handles = normalized_handles.map do |handle, normalized|
      existing_person = people[normalized]
      {
        handle: handle,
        reserved_handles: reservations[normalized] || [],
        existing_person: existing_person,
        is_applicant: existing_person&.bpguid == bpguid
      }
    end
  end

  private

  # Person's own check: asked only once Rails' pattern passes, so the field
  # says Person::EMAIL_MESSAGE once.
  def email_is_sendable
    return unless URI::MailTo::EMAIL_REGEXP.match?(email)

    errors.add(:email, Person::EMAIL_MESSAGE) unless EmailAddresses.sendable?(email)
  end

  def state_required_for_country
    if COUNTRIES_WITH_STATES.include?(country) && state.blank?
      errors.add(:state, "State is required for the selected country.")
    end
  end

  def stamp_updated_by
    person_id = Current.person_id
    return unless person_id

    if will_save_change_to_why_volunteer_review?
      self.reviewed_at = Time.zone.now
      self.review_person_id = person_id
    end

    self.updated_by_person_id = person_id
    self.updated_by_person_at = Time.zone.now
  end

  def record_update_log
    changes = audited_values
    return if changes.empty?

    ProspectiveApplicationLog.record(id, ProspectiveApplicationLog::ACTION_UPDATED, changes)
  end
end
