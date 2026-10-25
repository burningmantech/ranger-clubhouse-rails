# frozen_string_literal: true

class HandleReservation < ApplicationRecord
  self.table_name = "handle_reservation"
  self.audit_model = true

  RESERVATION_TYPE_BRC_TERM = "brc_term"
  RESERVATION_TYPE_DECEASED_PERSON = "deceased_person"
  RESERVATION_TYPE_DISMISSED_PERSON = "dismissed_person"
  RESERVATION_TYPE_OBSCENE = "obscene"
  RESERVATION_TYPE_PHONETIC_ALPHABET = "phonetic-alphabet"
  RESERVATION_TYPE_RADIO_JARGON = "radio_jargon"
  RESERVATION_TYPE_RANGER_TERM = "ranger_term"
  RESERVATION_TYPE_SLUR = "slur"
  RESERVATION_TYPE_TWII_PERSON = "twii_person"
  RESERVATION_TYPE_UNCATEGORIZED = "uncategorized"

  TYPE_BRC_TERM = RESERVATION_TYPE_BRC_TERM
  TYPE_DECEASED_PERSON = RESERVATION_TYPE_DECEASED_PERSON
  TYPE_DISMISSED_PERSON = RESERVATION_TYPE_DISMISSED_PERSON
  TYPE_OBSCENE = RESERVATION_TYPE_OBSCENE
  TYPE_PHONETIC_ALPHABET = RESERVATION_TYPE_PHONETIC_ALPHABET
  TYPE_RADIO_JARGON = RESERVATION_TYPE_RADIO_JARGON
  TYPE_RANGER_TERM = RESERVATION_TYPE_RANGER_TERM
  TYPE_SLUR = RESERVATION_TYPE_SLUR
  TYPE_TWII_PERSON = RESERVATION_TYPE_TWII_PERSON
  TYPE_UNCATEGORIZED = RESERVATION_TYPE_UNCATEGORIZED

  RESERVATION_TYPES = [
    RESERVATION_TYPE_BRC_TERM,
    RESERVATION_TYPE_DECEASED_PERSON,
    RESERVATION_TYPE_DISMISSED_PERSON,
    RESERVATION_TYPE_OBSCENE,
    RESERVATION_TYPE_PHONETIC_ALPHABET,
    RESERVATION_TYPE_RADIO_JARGON,
    RESERVATION_TYPE_RANGER_TERM,
    RESERVATION_TYPE_SLUR,
    RESERVATION_TYPE_TWII_PERSON,
    RESERVATION_TYPE_UNCATEGORIZED
  ].freeze

  TYPE_LABELS = {
    RESERVATION_TYPE_BRC_TERM => "BRC Term",
    RESERVATION_TYPE_DECEASED_PERSON => "Deceased person",
    RESERVATION_TYPE_DISMISSED_PERSON => "Dismissed person",
    RESERVATION_TYPE_OBSCENE => "Obscene word or phrase",
    RESERVATION_TYPE_PHONETIC_ALPHABET => "Phonetic alphabet word",
    RESERVATION_TYPE_RADIO_JARGON => "Radio jargon",
    RESERVATION_TYPE_RANGER_TERM => "Ranger term",
    RESERVATION_TYPE_SLUR => "Slur",
    RESERVATION_TYPE_TWII_PERSON => "TWII Person",
    RESERVATION_TYPE_UNCATEGORIZED => "Uncategorized"
  }.freeze

  validates :handle, presence: true, length: { maximum: 100 }
  validates :reservation_type, presence: true, inclusion: { in: RESERVATION_TYPES }, length: { maximum: 100 }
  validates :reason, length: { maximum: 255 }
  validates :twii_year, presence: true, if: :twii_person?
  validate :expires_on_must_be_a_valid_date
  validate :twii_year_must_be_an_integer
  validate :ensure_unique_reservation_key

  before_validation :normalize_fields
  before_validation :default_twii_expiry

  scope :active, -> { where(expires_on: Current.today..).or(where(expires_on: nil)) }
  scope :expired, -> { where(expires_on: ...Current.today) }

  class << self
    def find_for_query(query = {})
      params = (query || {}).to_h.with_indifferent_access
      scope = order(:handle)

      scope = scope.active if query_flag?(params, :active)
      scope = scope.expired if query_flag?(params, :expired)
      scope = scope.where(reservation_type: params[:reservation_type]) if params[:reservation_type].present?
      scope = scope.where(twii_year: params[:twii_year]) if params[:twii_year].present?

      scope
    end

    def retrieve_active_by_handle
      active.order(:handle).to_a.group_by(&:normalized_handle)
    end

    def retrieve_all_by_normalized_handle(normalized_handle)
      active.where(normalized_handle: normalized_handle).order(:handle)
    end

    def handle_type_exists?(handle, type, twii_year = nil)
      scope = active.where(
        normalized_handle: WordUtils.normalize_word(handle),
        reservation_type: type
      )
      scope = scope.where(twii_year: twii_year) if type == RESERVATION_TYPE_TWII_PERSON
      scope.exists?
    end

    def record_deceased(callsign)
      normalized_handle = WordUtils.normalize_word(callsign)
      return if where(
        normalized_handle: normalized_handle,
        reservation_type: RESERVATION_TYPE_DECEASED_PERSON
      ).exists?

      create!(
        handle: callsign,
        reservation_type: RESERVATION_TYPE_DECEASED_PERSON,
        expires_on: Current.today.advance(years: Person::GRIEVING_PERIOD_YEARS),
        reason: "marked deceased by #{Current.person&.callsign || "unknown"} on #{Current.today}"
      )
    end

    # September 15th of the third event year, counting this year's event as
    # the first. Applied to TWII entries saved without an expiration.
    def default_twii_expires_on
      Date.new(Current.today.year + 2, 9, 15)
    end

    def expire_handles!
      expired.order(:handle).map do |row|
        row.audit_reason = "expire handle"
        payload = {
          "handle" => row.handle,
          "type" => row.type_label,
          "reason" => row.reason,
          "expires_on" => row.expires_on&.to_s
        }
        row.destroy!
        payload
      end
    end

    alias_method :findForQuery, :find_for_query
    alias_method :retrieveActiveByHandle, :retrieve_active_by_handle
    alias_method :retrieveAllByNormalizedHandle, :retrieve_all_by_normalized_handle
    alias_method :handleTypeExists, :handle_type_exists?
    alias_method :recordDeceased, :record_deceased
    alias_method :expireHandles, :expire_handles!

    private

    def query_flag?(params, key)
      return false unless params.key?(key)

      ActiveModel::Type::Boolean.new.cast(params[key])
    end
  end

  def type_label
    TYPE_LABELS[reservation_type] || reservation_type
  end

  alias_method :getTypeLabel, :type_label

  def has_expired?
    expires_on.present? && expires_on < Current.today
  end

  def twii_person?
    reservation_type == RESERVATION_TYPE_TWII_PERSON
  end

  private

  def normalize_fields
    self.handle = handle.to_s.strip
    self.normalized_handle = WordUtils.normalize_word(handle)
    self.reason = reason.presence || ""
    self.expires_on = nil if expires_on_before_type_cast.blank?
    self.twii_year = nil if twii_year_before_type_cast.blank?
  end

  # Raw garbage in expires_on must fall through to the valid-date validation
  # instead of being papered over with the default.
  def default_twii_expiry
    return unless twii_person? && expires_on_before_type_cast.blank?

    self.expires_on = self.class.default_twii_expires_on
  end

  def expires_on_must_be_a_valid_date
    raw_value = expires_on_before_type_cast
    return if raw_value.blank? || expires_on.present? || raw_value.is_a?(Date)

    errors.add(:expires_on, "The expiration date is not a valid date.")
  end

  def twii_year_must_be_an_integer
    raw_value = twii_year_before_type_cast
    return if raw_value.blank? || raw_value.is_a?(Integer)
    return if raw_value.to_s.match?(/\A[+-]?\d+\z/)

    errors.add(:twii_year, "TWII year is not a number.")
  end

  def ensure_unique_reservation_key
    return if normalized_handle.blank? || reservation_type.blank?

    scope = self.class.where(normalized_handle:, reservation_type:)
    scope = scope.where(twii_year:) if twii_person?
    scope = scope.where.not(id:) if persisted?

    return unless scope.exists?

    errors.add(:handle, twii_person? ? "has already been reserved for this type and year" : "has already been reserved for this type")
  end
end
