# frozen_string_literal: true

class PersonPog < ApplicationRecord
  self.table_name = "person_pog"
  self.audit_model = true

  # Pog types
  POG_MEAL = "meal"
  POG_HALF_MEAL = "half-meal"
  POG_SHOWER = "shower"

  POGS = [POG_MEAL, POG_HALF_MEAL, POG_SHOWER].freeze

  POG_LABELS = {
    POG_MEAL => "Meal Pog",
    POG_HALF_MEAL => "1/2 Meal Pog",
    POG_SHOWER => "Shower Pog"
  }.freeze

  # Statuses
  STATUS_ISSUED = "issued"
  STATUS_REDEEMED = "redeemed"
  STATUS_CANCELLED = "cancelled"

  STATUSES = [STATUS_ISSUED, STATUS_REDEEMED, STATUS_CANCELLED].freeze

  STATUS_LABELS = {
    STATUS_ISSUED => "Issued",
    STATUS_REDEEMED => "Redeemed",
    STATUS_CANCELLED => "Cancelled"
  }.freeze

  # Attributes defaults
  attribute :notes, :string, default: ""
  attribute :status, :string, default: STATUS_ISSUED

  # Associations
  belongs_to :person
  belongs_to :issued_by, class_name: "Person"
  belongs_to :timesheet, optional: true

  # Validations
  validates :pog, inclusion: { in: POGS }
  validates :status, inclusion: { in: STATUSES }
  validate :timesheet_belongs_to_person, if: -> { timesheet_id.present? && timesheet_id_changed? }

  # Scopes
  # The pogs handed over during an event year. issued_at, not created_at: the
  # day a pog changed hands is what the Pogs pages count by. find_for_query
  # still scopes Person › Pogs by created_at.
  scope :issued_in, ->(year) { where_year("person_pog.issued_at", year) }

  before_validation :default_issued_at, on: :create

  def pog_label
    POG_LABELS[pog]
  end

  def status_label
    STATUS_LABELS[status]
  end

  # Normalize notes to blank string instead of nil
  def notes
    super.presence || ""
  end

  def notes=(value)
    super(value.presence || "")
  end

  # Find all the pogs given to a person
  def self.find_for_query(person_id: nil, year: nil)
    scope = includes(:issued_by).order(created_at: :desc)
    scope = scope.where(person_id:) if person_id
    scope = scope.where(created_at: Time.zone.local(year)...Time.zone.local(year + 1)) if year

    scope
  end

  # Distinct calendar years a person has been issued pogs. The year is taken in the
  # app timezone so the dropdown, the find_for_query range filter, and the issued-at
  # display all agree on which year a record belongs to.
  def self.years_for_person(person_id)
    where(person_id: person_id).pluck(:created_at).compact.map { |time| time.in_time_zone.year }.uniq
  end

  private

  def default_issued_at
    self.issued_at = Time.current if issued_at.blank?
  end

  def timesheet_belongs_to_person
    entry = Timesheet.find_by(id: timesheet_id)

    if entry.nil?
      errors.add(:timesheet_id, "Timesheet does not exist")
    elsif entry.person_id != person_id
      errors.add(:timesheet_id, "Timesheet does not belong to person")
    end
  end
end
