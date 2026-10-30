require "argon2"

class Person < ApplicationRecord
  include ActiveModel::Serializers::JSON
  include GenderHelper
  include Pronouns

  self.table_name = "person"
  self.audit_model = true

  # Never copied into the action log: the secrets, the sign-in timestamps, and
  # the two lookup columns that only repeat the callsign in another shape.
  #
  # The sms codes belong here for the same reason as the password. They are
  # checked to confirm a phone number, so anyone who could read one out of the
  # log could finish somebody else's verification.
  self.audit_exclude = %w[
    password logged_in_at last_seen_at
    callsign_normalized callsign_soundex
    sms_code sms_on_playa_code sms_off_playa_code
  ].freeze

  # memory cost is a power of 2
  ARGON2_MEMORY_COST = 13

  normalizes :email, with: ->(e) { e.strip.downcase }

  has_many :sessions, dependent: :destroy
  has_many :passkeys, class_name: "PersonPasskey", dependent: :destroy

  # Constants for status values
  ACTIVE = "active"
  ALPHA = "alpha"
  AUDITOR = "auditor"
  BONKED = "bonked"
  ECHELON = "echelon"
  DECEASED = "deceased"
  DISMISSED = "dismissed"
  INACTIVE = "inactive"
  INACTIVE_EXTENSION = "inactive extension"
  PAST_PROSPECTIVE = "past prospective"
  PROSPECTIVE = "prospective"
  RESIGNED = "resigned"
  RETIRED = "retired"
  SUSPENDED = "suspended"
  UBERBONKED = "uberbonked"

  # Deprecated statuses. Kept so historical rows and queries can still name
  # them, but deliberately left out of ALL_STATUSES -- the person.status enum
  # has no such member, so anything that offers or validates them would only
  # produce a status the database refuses to store.
  PROSPECTIVE_WAITLIST = "prospective waitlist"
  VINTAGE = "vintage"

  # Status arrays
  LIVE_STATUSES = [
    ACTIVE, ALPHA, INACTIVE, INACTIVE_EXTENSION, ECHELON,
    PAST_PROSPECTIVE, PROSPECTIVE, RETIRED
  ]

  ACTIVE_STATUSES = [
    ACTIVE, INACTIVE, INACTIVE_EXTENSION, RETIRED
  ].freeze

  TRAINING_STATUSES = [
    ACTIVE, INACTIVE, INACTIVE_EXTENSION, RETIRED, PROSPECTIVE, ALPHA
  ].freeze

  LOCKED_STATUSES = [
    DECEASED, DISMISSED, RESIGNED, SUSPENDED, UBERBONKED
  ].freeze

  # Statuses not allowed to be messaged.
  NO_MESSAGES_STATUSES = [
    AUDITOR, BONKED, DECEASED, DISMISSED, PAST_PROSPECTIVE,
    RESIGNED, SUSPENDED, UBERBONKED
  ].freeze

  CALLSIGN_MAX_LENGTH = 64

  # Status not allowed to be found for contact searches -- but exclusion
  # from this list does not mean the person is allowed to be messaged
  # (see NO_MESSAGE_STATUS).
  NO_SEARCH_FOR_CONTACT_STATUSES = [
    AUDITOR, BONKED, DISMISSED, PAST_PROSPECTIVE, UBERBONKED
  ].freeze

  ONLY_BASIC_PII_REQUIRED_STATUSES = [
    DECEASED, DISMISSED, RESIGNED, RETIRED
  ].freeze

  # Only these countries divide into states/provinces the Clubhouse asks for,
  # matching the upstream StateForCountry validation rule.
  COUNTRIES_REQUIRING_STATE = %w[US CA AU].freeze

  DEACTIVATED_STATUSES = [
    BONKED, DECEASED, DISMISSED, PAST_PROSPECTIVE, RESIGNED, UBERBONKED
  ].freeze

  # Statuses that may never be given a shift, BMID, or radio at the HQ
  # Window (Ember person.canStartShift). Deliberately allows
  # Alphas/Prospectives — their shifts may only be started by Mentors.
  SHIFT_BLOCKED_STATUSES = [
    AUDITOR, SUSPENDED, *DEACTIVATED_STATUSES
  ].freeze

  # Callsigns that belong to bookkeeping accounts and temporary laminates
  # rather than to a person. Reports listing people leave them out.
  #
  # \A rather than ^, which in Ruby matches at every line start: an embedded
  # newline would otherwise let a real callsign slip past the check.
  TEST_CALLSIGN = /\A(ROC Monitor|testing|lam #|temp \d+)|\(test\)/i

  # Every status that may be assigned and validated. Deprecated statuses are
  # excluded on purpose -- see PROSPECTIVE_WAITLIST and VINTAGE above.
  ALL_STATUSES = [
    ACTIVE, ALPHA, AUDITOR, BONKED, ECHELON, DECEASED, DISMISSED,
    INACTIVE, INACTIVE_EXTENSION, PAST_PROSPECTIVE, PROSPECTIVE,
    RESIGNED, RETIRED, SUSPENDED, UBERBONKED
  ].freeze

  WORKING_STATUSES = [
    ACTIVE,
    ALPHA,
    INACTIVE,
    INACTIVE_EXTENSION,
    RETIRED,
    ECHELON
  ].freeze

  RELEASE_CALLSIGN_WARNING_STATUSES = [
    ACTIVE,
    ECHELON,
    INACTIVE,
    INACTIVE_EXTENSION,
    SUSPENDED
  ].freeze

  # SMS column names (unified single-number schema)
  SMS_NUMBER = "sms_number"
  SMS_CODE = "sms_code"
  SMS_VERIFIED = "sms_verified"
  SMS_STOPPED = "sms_stopped"

  # Said in place of Rails' "is invalid": "Primary phone must be only a phone
  # number, ...". A key in config/locales/en.yml, not a string, so the message
  # names its field like every other; a page that calls the field something
  # else asks ValidationMessage for its own name.
  PHONE_MESSAGE = :phone_invalid

  # Said in place of Rails' "is invalid", and for an address that passes Rails'
  # pattern but that no mail could reach (EmailAddresses.sendable?): "Email
  # must be a full address that mail can reach, ...". A key, like PHONE_MESSAGE.
  EMAIL_MESSAGE = :email_invalid

  # The Paycom Employee ID that clears someone to work paid shifts without pay.
  UNPAID_EMPLOYEE_ID = "0"

  # Token expiration times (in seconds)
  RESET_PASSWORD_EXPIRE = 3600 * 2
  PNV_INVITATION_EXPIRE = 3600 * 24 * 14
  GRIEVING_PERIOD_YEARS = 5

  # Role operations
  REMOVE_ALL = 0
  ADD_NEW_USER = 1

  # Associations
  has_many :person_swags, dependent: :destroy
  has_many :swags, through: :person_swags

  # Associations with shirt swag (belongs_to relationships)
  belongs_to :tshirt_swag, class_name: "Swag", optional: true
  belongs_to :tshirt_secondary_swag, class_name: "Swag", optional: true
  belongs_to :long_sleeve_swag, class_name: "Swag", optional: true

  # Photo associations
  # The current photo is the most recent approved photo — the person_photo_id
  # column is a legacy Laravel pointer and is no longer maintained. Approving a
  # photo deletes the person's other photos (PersonPhoto#cleanup_photos), so at
  # most one approved photo exists per person.
  has_many :person_photos, class_name: "PersonPhoto", dependent: :destroy
  has_one :photo, -> { current_first }, class_name: "PersonPhoto"
  has_one :profile_photo_attachment, -> { current_first.with_attached_profile }, class_name: "PersonPhoto"
  has_one :avatar_photo_attachment, -> { current_first.with_attached_avatar }, class_name: "PersonPhoto"
  has_one :submitted_photo, -> { submitted }, class_name: "PersonPhoto"

  has_many :certification, through: :person_certification
  has_many :email_history, dependent: :destroy
  has_many :motd, through: :person_motd
  has_many :person_banner, dependent: :delete_all
  has_many :person_certification, dependent: :delete_all
  has_many :person_fka, -> { order(:fka_normalized) }, dependent: :destroy
  has_many :person_language, dependent: :delete_all
  has_many :person_favorite, dependent: :delete_all
  has_many :person_page_visit, dependent: :delete_all
  has_many :person_motd, dependent: :delete_all
  # The person's place in each message thread: a row left behind named nobody,
  # and every other member's list and pane failed on it (review finding 7).
  has_many :person_message_member, dependent: :delete_all
  has_many :person_position, dependent: :delete_all
  has_many :person_role, dependent: :delete_all
  has_many :person_slot, dependent: :delete_all
  has_many :person_team, dependent: :delete_all
  has_many :position, through: :person_position
  has_many :role, through: :person_role
  has_many :slot, through: :person_slot
  has_many :team, through: :person_team
  has_many :timesheet, dependent: :destroy
  # The rest of what an account owns, Clubhouse 2's ASSOC_TABLES list; each
  # table has a foreign key to person, so a child left out here refuses the
  # delete instead of dangling. In one statement each: a deleted person has no
  # years or caches left to recompute.
  has_many :access_documents, dependent: :destroy  # takes its change log
  has_many :bmids, dependent: :delete_all
  has_many :person_awards, dependent: :delete_all
  has_many :person_events, dependent: :delete_all
  has_many :person_intakes, dependent: :delete_all
  has_many :person_intake_notes, dependent: :delete_all
  has_many :person_mentors, dependent: :delete_all
  has_many :person_online_courses, dependent: :delete_all
  has_many :team_managers, dependent: :delete_all
  has_many :timesheet_missings, dependent: :destroy  # takes its notes
  has_many :trainee_notes, dependent: :delete_all
  has_many :trainee_statuses, dependent: :delete_all
  has_many :trainer_statuses, dependent: :delete_all
  has_many :person_alerts, dependent: :delete_all
  has_many :person_assets, dependent: :delete_all
  has_many :person_pogs, dependent: :delete_all
  has_many :person_pods, dependent: :delete_all
  has_many :person_on_sites, dependent: :delete_all
  has_many :oauth_codes, dependent: :delete_all
  has_many :provisions, dependent: :delete_all

  # Validations
  validates :callsign, presence: true, length: { maximum: CALLSIGN_MAX_LENGTH }

  validates :callsign, uniqueness: true, if: -> { callsign.present? and (new_record? or callsign_changed?) }
  validates :email, presence: true, length: { maximum: 255 },
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: EMAIL_MESSAGE }
  validates :email, uniqueness: true, if: -> { new_record? or (email.present? and email_changed?) }
  # Held only to an address being changed, like the phones below, so one stored
  # before addresses were checked never blocks saving something else.
  validate :email_is_sendable, if: :email_changed_beyond_case?

  validates :first_name, presence: true, length: { maximum: 25 }
  validates :last_name, presence: true, length: { maximum: 25 }
  validates :mi, length: { maximum: 10 }
  validates :status, presence: true, inclusion: { in: ALL_STATUSES }
  validates :gender_identity, inclusion: { in: GENDER_TYPES }
  validates :gender_custom, length: { maximum: 32 }
  validates :home_phone, presence: true, length: { maximum: 25 }
  validates :alt_phone, length: { maximum: 25 }
  # Held only to a number being changed, so one stored before numbers were
  # checked never blocks saving something else. format: :e164 because the
  # validator parses without a country, and would pass bare digits that
  # PhoneFormatter refused.
  validates :home_phone, phone: { format: :e164, allow_blank: true, message: PHONE_MESSAGE }, if: :home_phone_changed?
  validates :alt_phone, phone: { format: :e164, allow_blank: true, message: PHONE_MESSAGE }, if: :alt_phone_changed?

  # Conditional validations for address
  validates :street1, presence: true, length: { maximum: 191 }, unless: :only_basic_pii_required?
  validates :apt, presence: false, length: { maximum: 191 }, unless: :only_basic_pii_required?
  validates :street2, presence: false, length: { maximum: 191 }, unless: :only_basic_pii_required?
  validates :city, presence: true, length: { maximum: 191 }, unless: :only_basic_pii_required?
  validates :state, length: { maximum: 191 }
  validates :state, presence: true, if: :state_required?
  validates :zip, presence: true, length: { maximum: 191 }, unless: :only_basic_pii_required?
  validates :country, presence: true, length: { maximum: 191 }, unless: :only_basic_pii_required?

  validates :camp_location, length: { maximum: 200 }

  validates :callsign_pronounce, length: { maximum: 20 }

  # Callbacks
  before_validation :clear_custom_fields
  before_validation :store_phones_as_e164

  before_save :set_status_date_if_changed
  before_save :clear_bouncing_on_email_change
  before_save :set_vanity_changed_at
  before_save :handle_past_prospective_status
  before_save :clear_callsign_pronunciation
  before_save :update_callsign_fka
  before_update :clear_sms_flags

  after_save :log_status_change
  after_save :log_email_change
  after_save :log_password_change
  after_save :log_on_site_change

  # Scopes
  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :live, -> { where(status: LIVE_STATUSES) }
  scope :locked, -> { where(status: LOCKED_STATUSES) }
  # #messaging_permitted? in SQL: change both together.
  scope :messageable, -> { where.not(status: NO_MESSAGES_STATUSES).where.not(last_seen_at: nil) }
  scope :by_callsign, ->(callsign) { where(callsign_normalized: normalize_callsign(callsign)).first }
  scope :by_status, ->(statuses) { where(status: Array(statuses)) }
  scope :basic_info, -> { select("id", "callsign", "status") }

  # Attributes that should be serialized as coder: JSON
  serialize :years_as_contributor, coder: JSON
  serialize :years_as_ranger, coder: JSON
  serialize :years_combined, coder: JSON
  serialize :years_of_awards, coder: JSON
  serialize :years_of_service, coder: JSON

  serialize :years_of_signups, coder: JSON
  serialize :years_seen, coder: JSON

  # The column is nullable with no default, and every reader treats "no data
  # yet" and "never rangered" alike -- several call .any? bare. Reading nil as
  # [] here retires the ad-hoc is_a?(Array) guards.
  def years_as_ranger
    super || []
  end

  # Virtual attributes
  attr_accessor :has_reviewed_pi
  attr_accessor :role_manager

  class << self
    # Find person by callsign
    def retrieve_by_callsign(callsign)
      find_by(callsign_normalized: WordUtils.normalize_word(callsign))
    end

    # The one person a typed callsign names: the exact callsign (unique), else
    # the only callsign that matches once spacing and punctuation are dropped.
    # Nil when that matches two people ("Fire-Fly" and "Fire Fly"), when nothing
    # is left to match ("!!!", which would find every callsign that normalizes
    # to ""), or when the value is not a String at all.
    def resolve_callsign(callsign)
      return nil unless callsign.is_a?(String)

      person = find_by(callsign:)
      return person if person

      normalized = WordUtils.normalize_word(callsign)
      return nil if normalized.empty?

      matches = where(callsign_normalized: normalized).limit(2).to_a
      matches.first if matches.one?
    end

    # Find person ID by callsign
    def find_id_by_callsign(callsign)
      Person.where(callsign_normalized: WordUtils.normalize_word(callsign)).pluck(:id).first
    end

    # Bulk lookup by callsigns
    def find_all_by_callsigns(callsigns)
      where(callsign_normalized: callsigns.map { |c| WordUtils.normalize_word(c) })
        .index_by { |person| person.callsign_normalized.downcase }
    end

    # Check if email exists
    def email_exists?(email)
      exists?(email: email)
    end

    # Search with pagination
    def find_for_query(params = {})
      query = order(:callsign)

      if params[:callsign]
        query = query.by_callsign(params[:callsign])
      end

      if params[:statuses]
        statuses = params[:statuses].split(",")
        query = query.by_status(statuses)
      end

      if params[:exclude_statuses]
        exclude_statuses = params[:exclude_statuses].split(",")
        query = query.where.not(status: exclude_statuses)
      end

      total = query.count
      limit = (params[:limit] || 50).to_i
      offset = (params[:offset] || 0).to_i

      people = query.limit(limit).offset(offset)

      {
        people: people,
        total: total,
        limit: limit
      }
    end
  end

  # How long a website may use a sign-in token to ask who signed in. One call
  # right after the sign-in is all any of them makes.
  SSO_ACCESS_TOKEN_LIFETIME = 1.hour

  # The token a website gets for a redeemed sign-in code. Signed, dated and
  # kept nowhere: find_by_token_for reads the person and the expiry back out.
  generates_token_for :sso_access, expires_in: SSO_ACCESS_TOKEN_LIFETIME

  # The links that set a password: the reset email's and the welcome email's.
  # Signed and dated like the one above, and kept nowhere, so nothing in the
  # database is a sign-in. Each carries the tail of the password hash it was
  # made against: once the password changes, every link made before stops
  # opening, used or not.
  PASSWORD_LINKS = { password_reset: RESET_PASSWORD_EXPIRE, invitation: PNV_INVITATION_EXPIRE }.freeze
  PASSWORD_LINKS.each do |purpose, lifetime|
    generates_token_for(purpose, expires_in: lifetime.seconds) { password&.last(10) }
  end

  # Whoever a password link is for, or nil for a link that is spent, expired,
  # altered, or no link at all. A token that is not text (token[]=x) is no
  # link either: the verifier would raise on it rather than refuse it.
  def self.find_by_password_link(token)
    return nil unless token.is_a?(String) && token.present?

    PASSWORD_LINKS.each_key { |purpose| (person = find_by_token_for(purpose, token)) and return person }
    nil
  end

  # What a website is told about the person its token stands for. The keys
  # are the ones the learning site and the HQ ticket desk map their fields
  # from, so they stay as Clubhouse 2 spelled them, plus the standard sub.
  def sso_claims
    {
      sub: id.to_s,
      chid: id,
      username: callsign_normalized.to_s.downcase,
      email: email,
      given_name: is_ranger? ? "Ranger" : status.to_s.upcase_first,
      family_name: callsign
    }
  end

  # Only an Argon2 hash verifies. A blank password is an account whose
  # salted-SHA1 hash was retired (RetireSha1Passwords); its holder sets a new
  # one through Forgot.
  def authenticate(password)
    return false if self.password.blank?

    Argon2::Password.verify_password(password, self.password)
  rescue Argon2::ArgonHashFail
    false
  end

  def password=(new_password)
    write_attribute(:password, Argon2::Password.new(m_cost: ARGON2_MEMORY_COST).create(new_password))
  end

  def is_applicant?
    [PROSPECTIVE, ALPHA].include?(status)
  end

  # Upstream name for a Prospective New Volunteer; ported templates call this.
  def pnv? = is_applicant?

  def can_start_shift? = SHIFT_BLOCKED_STATUSES.exclude?(status)

  # May not sign in, and is signed out on the next request if signed in.
  def locked? = LOCKED_STATUSES.include?(status)

  def is_ranger?
    [ACTIVE, INACTIVE, INACTIVE_EXTENSION, RETIRED].include?(status)
  end

  def is_active?
    status == ACTIVE
  end

  def is_echelon?
    status == ECHELON
  end

  def can_work?
    WORKING_STATUSES.include?(status)
  end

  def is_contributor_or_applicant?
    is_ranger? || is_applicant? || is_echelon?
  end

  # Rangers and Echelon are the people offered the Clubhouse mailbox: the
  # Messages menu item and the navbar's unread envelope ask this, so the two
  # cannot disagree about who sees them.
  def mailbox_user?
    is_ranger? || is_echelon?
  end

  def is_auditor?
    status == AUDITOR
  end

  # Ticketing requires a linked Burner Profile (auditors have no package).
  def missing_bpguid?
    status != AUDITOR && bpguid.blank?
  end

  def deceased?
    status == DECEASED
  end

  def retired?
    status == RETIRED
  end

  def prospective?
    status == PROSPECTIVE
  end

  def past_prospective?
    status == PAST_PROSPECTIVE
  end

  def is_any_bonked?
    status == BONKED || status == UBERBONKED
  end

  # Personal information
  def desired_first_name
    preferred_name.present? ? preferred_name : first_name
  end

  # Squished, so a blank first or last name leaves no stray space.
  def desired_full_name
    "#{desired_first_name} #{last_name}".squish
  end

  def has_reviewed_pi?
    pi_reviewed_for_dashboard_at&.year == Current.year
  end

  def has_role?(role_or_roles)
    return Current.has_role?(role_or_roles) if Current.person_id == id

    @role_manager ||= RoleManager.retrieve(self)
    @role_manager.has_role?(role_or_roles)
  end

  # The roles before an unsigned NDA wiped them (RoleManager#has_raw_role?).
  def has_raw_role?(role_or_roles)
    return Current.has_raw_role?(role_or_roles) if Current.person_id == id

    @role_manager ||= RoleManager.retrieve(self)
    @role_manager.has_raw_role?(role_or_roles)
  end

  # Does the person hold any permission built on the given base -- any ART
  # Survey Mgmt permission, say, whichever training it was composed for?
  def has_role_base?(base)
    return Current.has_role_base?(base) if Current.person_id == id

    @role_manager ||= RoleManager.retrieve(self)
    @role_manager.has_role_base?(base)
  end

  # Callsign management
  #
  # taken: extra callsigns to treat as unavailable. A preview generates a whole
  # batch without saving anyone, so in-batch collisions are invisible to
  # exists? -- the caller passes the handles it has already handed out.
  def reset_callsign(taken: nil)
    last_name_clean = WordUtils.convert_diacritics(last_name)
    first_letter = WordUtils.convert_diacritics(desired_first_name)[0]
    year = Current.year % 100

    (0..9).each do |try|
      new_callsign = last_name_clean
      new_callsign += (try + 1).to_s if try > 0
      new_callsign += first_letter + year.to_s

      case status
      when BONKED
        new_callsign += "B"
      when AUDITOR
        new_callsign += "(NR)"
      end

      unless self.class.exists?(callsign: new_callsign) || taken&.include?(new_callsign)
        self.callsign = new_callsign
        return true
      end
    end

    false
  end

  # Utility methods - enhanced implementations
  def formerly_known_as_array(filter = false)
    names = person_fka.order(:fka_normalized).pluck(:fka)
    filter ? PersonFka.filter_out_irrelevant(names) : names
  end

  def known_pnvs_array
    WordUtils.split_commas(known_pnvs)
  end

  def known_rangers_array
    WordUtils.split_commas(known_rangers)
  end

  def add_year_to_field(field_name, year)
    years = send(field_name)
    years << year unless years.include?(year)
    send("#{field_name}=", years.sort)
  end

  def remove_year_from_field(field_name, year)
    years = self[field_name]
    years.delete(year)
    send("#{field_name}=", years)
  end

  def has_custom_gender?
    gender_identity == GENDER_CUSTOM
  end

  def gender_not_stated?
    gender_identity == GENDER_NONE
  end

  def has_custom_pronouns?
    pronouns == PRONOUNS_CUSTOM
  end

  def needs_profile_review?
    return false if ONLY_BASIC_PII_REQUIRED_STATUSES.include?(status)

    !has_reviewed_pi? && LIVE_STATUSES.include?(status)
  end

  def callsign=(callsign)
    return unless callsign.present?

    # Clean up Microsoft special characters
    cleaned = callsign.tr("«»" + '‚‛""„‟‹›–—', '<<>>\'\'\'\'""""<<>>--')
    cleaned = cleaned.gsub("…", "...").strip

    super(cleaned)
    self.callsign_normalized = WordUtils.normalize_word(cleaned)
    self.callsign_soundex = WordUtils.metaphone(callsign_normalized)
  end

  # A cleared ID is stored as nil, never "", and the ends are trimmed -- of
  # no-break and zero-width spaces too, which the database reads past -- so "0 "
  # is saved as the "0" it means. A setter rather than normalizes, which would
  # also rewrite update_column, update_all and where, so a row written around
  # the model could no longer be found by the payroll reports.
  def employee_id=(id)
    super(StripAttributes.strip(id))
  end

  def has_photo?
    photo&.original
  end

  def profile_photo
    return nil unless profile_photo_attachment&.profile&.attached?
    profile_photo_attachment.profile
  end

  def avatar_photo
    return nil unless avatar_photo_attachment&.avatar&.attached?
    avatar_photo_attachment.avatar
  end

  def has_submitted_photo?
    submitted_photo&.status == PersonPhoto::SUBMITTED && submitted_photo&.avatar
  end

  def messaging_permitted?
    last_seen_at && !messages_barred?
  end

  # Does the person's status take no messages (NO_MESSAGES_STATUSES)?
  def messages_barred?
    NO_MESSAGES_STATUSES.include?(status)
  end

  # =========================================================================
  # SMS Helper Methods
  # =========================================================================

  # Does the person have a verified, non-stopped SMS number?
  def sms_usable?
    sms_number.present? && sms_verified? && !sms_stopped?
  end

  # Reset SMS verification state (called when number changes)
  def reset_sms_verification!
    self.sms_verified = false
    self.sms_stopped = false
    self.sms_code = nil
  end

  # Mark the SMS number as verified
  def mark_sms_verified!
    update_columns(sms_verified: true)
  end

  # Set the stopped flag
  def mark_sms_stopped!(stopped = true)
    update_columns(sms_stopped: stopped)
  end

  # Generate and store a 4-digit verification code
  def generate_sms_code!
    code = 4.times.map { rand(10) }.join
    self.sms_code = code
    code
  end

  # Find a person by their SMS number
  def self.find_by_sms_number(number)
    where(sms_number: number).first
  end

  def home_phone_formatted
    PhoneFormatter.format(home_phone)
  end

  def alt_phone_formatted
    PhoneFormatter.format(alt_phone)
  end

  # Whether a full mailing address has to be given. People who have left the
  # department keep whatever is already on file, so their forms do not ask for
  # one. Mirrors the address validations so a form marks exactly the fields a
  # save will insist on.
  def mailing_address_required?
    !only_basic_pii_required?
  end

  # Countries outside the US, Canada, and Australia have no state to give.
  def state_required?
    !only_basic_pii_required? && COUNTRIES_REQUIRING_STATE.include?(country)
  end

  private

  def only_basic_pii_required?
    ONLY_BASIC_PII_REQUIRED_STATUSES.include?(status) &&
      (Current.person.nil? || Current.has_role?([Role::ADMIN, Role::VC]))
  end

  def clear_custom_fields
    self.pronouns_custom = "" if pronouns != PRONOUNS_CUSTOM

    if gender_identity == GENDER_CUSTOM
      if gender_custom.blank?
        self.gender_identity = GENDER_NONE
      end
    else
      self.gender_custom = ""
    end
  end

  # Asked only once Rails' pattern passes: an address it refuses already has
  # EMAIL_MESSAGE, and the field says it once.
  def email_is_sendable
    return unless URI::MailTo::EMAIL_REGEXP.match?(email)

    errors.add(:email, EMAIL_MESSAGE) unless EmailAddresses.sendable?(email)
  end

  # normalizes :email applies on assignment, never to a value read from the
  # database, and Clubhouse 2 stored addresses as typed. The identity form sends
  # the address back on every save, so a stored "Name@GmailCom" sent back as it
  # was reads as changed to email_changed? -- but is the same address.
  def email_changed_beyond_case?
    email_changed? && email != Person.normalize_value_for(:email, email_was)
  end

  # Read against the mailing address, so "0121 496 0497" from someone in
  # Britain is a British number. One that cannot be read stays as typed, for
  # the checks above to turn back with the reader's own input in the field.
  def store_phones_as_e164
    self.home_phone = PhoneFormatter.e164(home_phone, country) || home_phone
    self.alt_phone = PhoneFormatter.e164(alt_phone, country) || alt_phone
  end

  def set_status_date_if_changed
    if status_changed?
      self.status_date = Current.time
    end
  end

  def clear_bouncing_on_email_change
    if email_changed?
      self.is_bouncing = false
    end
  end

  def set_vanity_changed_at
    if used_vanity_change_changed? && used_vanity_change?
      self.vanity_changed_at = Current.time
    end
  end

  def handle_past_prospective_status
    if status_changed? && status == PAST_PROSPECTIVE && !callsign_changed?
      reset_callsign
      self.callsign_approved = false
    end
  end

  def clear_callsign_pronunciation
    if callsign_changed? && !callsign_pronounce_changed?
      self.callsign_pronounce = ""
    end
  end

  def update_callsign_fka
    return true unless callsign_changed?
    return true if callsign_was.blank?

    record = person_fka.build(fka: callsign_was)
    # Assigned after build: PersonFka#fka= derives is_irrelevant from the
    # callsign's shape, and the override has to win over that default.
    override = fka_irrelevant_override
    record.is_irrelevant = override unless override.nil?
    record
  end

  # Whether the outgoing callsign stays searchable, porting the rules in
  # upstream Person::boot's saved callback. nil means "no opinion" -- let
  # PersonFka::IRRELEVANT_REGEXP judge the callsign on its shape alone.
  def fka_irrelevant_override
    if status_changed?
      return true if status_was == AUDITOR
      # A PNV handle is generated, so the regexp would bury it -- but it is the
      # only name the VC teams knew this person by, so it has to stay findable.
      return false if [PROSPECTIVE, ALPHA, BONKED].include?(status_was) && status == PAST_PROSPECTIVE

      nil
    elsif ACTIVE_STATUSES.include?(status)
      # A plain rename by an active Ranger: the old callsign is still how people
      # know them, whatever its shape.
      false
    end
  end

  # Both history hooks hang off the "updated" model event upstream. A brand new
  # account has no previous status or email to record, and both history tables
  # require one -- account creation writes its own opening status row instead.
  def log_status_change
    return if previously_new_record?

    if saved_change_to_status?
      old_status = saved_changes["status"][0]
      PersonStatusManagement.change(person: self, old_status: old_status, reason: audit_reason || "Status changed")
    end
  end

  def log_email_change
    return if previously_new_record?

    if saved_change_to_email?
      EmailHistory.record(id, saved_changes["email"][0], Current.person_id)
    end
  end

  # A password change is recorded on its own, because the password itself is
  # kept out of the action log and the entry would otherwise say nothing. A
  # brand new account is skipped -- the entry for creating it already covers
  # the password it was given.
  def log_password_change
    return if previously_new_record?
    return unless saved_change_to_password?

    ActionLog.record(Current.person_id, "auth-password-change", "Password changed", nil, id)
  end

  # Every on-site or off-site change, for the person's site log, in the same
  # transaction as the change itself. An account created on site counts: with
  # no row it would read as off site. The actor is the one the audit row names.
  def log_on_site_change
    return unless saved_change_to_on_site?

    PersonOnSite.record(self, audit_actor_id)
  end

  # A new number is unverified until proven otherwise -- but only clobber the
  # flags the caller did not set itself in this same save, or this wipes the
  # verification code generated alongside the number.
  def clear_sms_flags
    return unless sms_number_changed?

    self.sms_code = "" unless sms_code_changed?
    self.sms_stopped = false unless sms_stopped_changed?
    self.sms_verified = false unless sms_verified_changed?
  end
end
