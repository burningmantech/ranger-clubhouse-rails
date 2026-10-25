# frozen_string_literal: true

class TimesheetMissing < ApplicationRecord
  self.table_name = "timesheet_missing"

  # Review statuses
  STATUS_APPROVED = "approved"
  STATUS_REJECTED = "rejected"
  STATUS_PENDING = "pending"

  REVIEW_STATUSES = [STATUS_APPROVED, STATUS_REJECTED, STATUS_PENDING].freeze

  PARTNER_SHIFT_STARTS_WITHIN = 30 # minutes

  # Associations
  belongs_to :person
  belongs_to :position
  belongs_to :reviewer_person, class_name: "Person", optional: true
  belongs_to :create_person, class_name: "Person", optional: true
  belongs_to :partner_person, class_name: "Person", foreign_key: :partner, primary_key: :callsign, optional: true

  has_many :timesheet_missing_notes, dependent: :destroy
  has_many :notes, -> { where.not(type: TimesheetMissingNote::TYPE_ADMIN) }, class_name: "TimesheetMissingNote"
  has_many :admin_notes, -> { where(type: TimesheetMissingNote::TYPE_ADMIN) }, class_name: "TimesheetMissingNote"

  # Validations
  validates :person_id, presence: true
  validates :position_id, presence: true
  validates :on_duty, presence: true
  validates :off_duty, presence: true
  validates_datetime :off_duty, after: :on_duty, if: -> { off_duty.present? && on_duty.present? }
  validates :review_status, inclusion: { in: REVIEW_STATUSES }, allow_nil: true
  validates :partner, length: { maximum: 255 }, allow_blank: true

  validate :is_reason_provided?

  # Virtual attributes

  attribute :additional_notes, :string
  attribute :additional_admin_notes, :string
  attribute :additional_wrangler_notes, :string
  attribute :create_entry, :boolean
  attribute :new_on_duty, :string
  attribute :new_off_duty, :string
  attribute :new_position_id, :integer

  attr_accessor :time_warnings

  # Callbacks
  after_save :record_notes

  # Scopes
  scope :for_year, ->(year) { where_year("on_duty", year) }
  scope :for_person, ->(person_id) { where(person_id: person_id) }
  scope :pending, -> { where(review_status: STATUS_PENDING) }
  scope :ordered_by_on_duty, -> { order(:on_duty) }

  class << self
    # Find timesheet missing requests based on criteria
    def find_for_query(query)
      person_id = query[:person_id]
      year = query[:year]
      include_admin_notes = query[:include_admin_notes]
      check_times = query[:check_times]

      sql = includes(:position, :reviewer_person, :notes)

      sql = sql.for_person(person_id) if person_id.present?
      sql = sql.for_year(year) if year.present?
      sql = sql.includes(:admin_notes) if include_admin_notes

      rows = sql.ordered_by_on_duty

      rows.each(&:check_times) if check_times

      rows
    end

    # Find the missing timesheet requests for a person OR all outstanding requests for a given year
    def retrieve_for_person_or_all_for_year(person_id, year)
      sql = includes(:position, :person, :create_person, :reviewer_person, :partner_person)
              .for_year(year)
              .ordered_by_on_duty

      rows = person_id.present? ? sql.for_person(person_id) : sql.pending
      rows.sort_by { |r| r.person.callsign.downcase }
    end
  end

  # Duration in seconds
  def duration
    return 0 unless on_duty.present? && off_duty.present?

    (off_duty - on_duty).to_i
  end

  # Calculate potential credits
  def credits
    return 0.0 unless on_duty.present? && off_duty.present?

    PositionCredit.compute_credits(
      position_id,
      on_duty.to_i,
      off_duty.to_i,
      on_duty.year
    )
  end

  # Check on the times to see if everything makes sense
  def check_times
    return unless on_duty.present? && off_duty.present?

    self.time_warnings = Slot.check_date_time_for_position(position_id, on_duty, off_duty)
  end

  # Get partner information with shift matching
  def partner_info
    return nil if partner.blank?

    # Check for N/A variants
    return nil if partner.strip.match?(/\A(na|n\/a|no partner|none)\z/i)

    # Split by common delimiters
    people = partner.split(/\band\b|\s*[&+|]\s*/i)

    partners = []

    people.each do |name|
      name = name.strip
      next if name.blank?

      # Try exact match first
      found_person = Person.find_by(callsign: name)

      # Try without spaces
      if found_person.nil? && name.include?(" ")
        found_person = Person.find_by(callsign: name.delete(" "))
      end

      # Try metaphone lookup
      if found_person.nil?
        metaphone = WordUtils.metaphone(name)
        found_person = Person.find_by(callsign_soundex: metaphone) if metaphone.present?
      end

      if found_person.nil?
        partners << { "callsign" => name }
        next
      end

      info = {
        callsign: found_person.callsign,
        person_id: found_person.id,
        name:
      }

      # Try to find partner's shift
      partner_shift = Timesheet.find_shift_within_minutes(found_person.id, on_duty, PARTNER_SHIFT_STARTS_WITHIN)

      if partner_shift.present?
        info.merge!(
          timesheet_id: partner_shift.id,
          position_title: partner_shift.position.title,
          position_id: partner_shift.position_id,
          on_duty: partner_shift.on_duty.to_s,
          off_duty: partner_shift.off_duty.to_s
        )
      end

      partners << info
    end

    partners
  end

  # Normalize partner field
  def partner=(value)
    super(value.present? ? value.strip : "")
  end

  def status_approved?
    review_status == STATUS_APPROVED
  end

  def status_pending?
    review_status == STATUS_PENDING
  end

  def status_rejected?
    review_status == STATUS_REJECTED
  end

  private

  def record_notes
    user_id = Current.person_id
    entry_id = id

    if additional_notes.present?
      note_type = user_id == person_id ? TimesheetMissingNote::TYPE_USER : TimesheetMissingNote::TYPE_HQ_WORKER
      TimesheetMissingNote.record(entry_id, user_id, additional_notes.strip, note_type)
    end

    if additional_admin_notes.present?
      TimesheetMissingNote.record(entry_id, user_id, additional_admin_notes.strip, TimesheetMissingNote::TYPE_ADMIN)
    end

    if additional_wrangler_notes.present?
      TimesheetMissingNote.record(entry_id, user_id, additional_wrangler_notes.strip, TimesheetMissingNote::TYPE_WRANGLER)
    end
  end

  def is_reason_provided?
    unless notes.any? { |note| note.type == TimesheetNote::TYPE_USER } || additional_notes.present?
      errors.add(:additional_notes, "Give a reason why a new timesheet should be added.")
    end
  end
end
