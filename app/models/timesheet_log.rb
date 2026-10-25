# frozen_string_literal: true

class TimesheetLog < ApplicationRecord
  self.table_name = "timesheet_log"

  # Actions
  UNCONFIRMED = "unconfirmed"       # Entire timesheet marked unconfirmed (usually an entry was updated/created)
  CONFIRMED = "confirmed"           # Entire timesheet marked confirmed

  SIGNON = "signon"                 # Timesheet entry created via shift start
  SIGNOFF = "signoff"               # Shift was ended
  UPDATE = "update"                 # Timesheet entry updated
  DELETE = "delete"                 # Timesheet entry deleted
  DELETE_MISTAKE = "delete-mistake" # Timesheet entry deleted due to accidental creation

  UNVERIFIED = "unverified"         # Entry was marked unverified
  VERIFY = "verify"                 # Entry marked verified (aka correct)

  CREATED = "created"               # Created via bulk update or missing timesheet request

  # Via sources
  VIA_BULK_UPLOAD = "bulk-upload"       # Entry created via Bulk Uploader
  VIA_MISSING_ENTRY = "missing-entry"   # Entry created via Missing Timesheet Request

  ACTIONS = [
    CONFIRMED,
    CREATED,
    DELETE,
    DELETE_MISTAKE,
    SIGNOFF,
    SIGNON,
    UNCONFIRMED,
    UNVERIFIED,
    UPDATE,
    VERIFY
  ].freeze

  # Associations
  belongs_to :person
  belongs_to :creator, class_name: "Person", foreign_key: :create_person_id, optional: true
  belongs_to :timesheet, optional: true

  # Serialization
  serialize :data, coder: JSON

  # Scopes
  scope :for_person, ->(person_id) { where(person_id: person_id) }
  scope :for_year, ->(year) { where(year: year) }
  scope :with_timesheet, -> { where.not(timesheet_id: nil) }
  scope :without_timesheet, -> { where(timesheet_id: nil) }
  scope :ordered, -> { order(:created_at) }

  class << self
    # Find the logs for a person & year
    def find_for_person_year(person_id, year)
      timesheet_logs = includes(:person, :creator, timesheet: :position)
        .left_joins(:timesheet)
        .with_timesheet
        .for_person(person_id)
        .for_year(year)
        .ordered

      # Find confirmation logs that might be in a different year
      other_logs = includes(:person, :creator)
        .for_person(person_id)
        .where_year("created_at", year)
        .without_timesheet
        .ordered

      [timesheet_logs, other_logs]
    end

    # Update the year for all logs of a timesheet
    def update_year(timesheet_id, year)
      where(timesheet_id: timesheet_id).update_all(year: year)
    end

    # Record a timesheet action
    def record(action, person_id, user_id, timesheet_id, data, year = 0)
      create!(
        action: action,
        person_id: person_id,
        create_person_id: user_id,
        timesheet_id: timesheet_id,
        data: data.is_a?(Hash) ? data : { message: data },
        year: year.positive? ? year : Current.year,
        created_at: Current.time
      )
    end
  end

  # Decode and enhance data with position titles
  def decode_data
    return nil unless data.present?

    decoded = data.deep_dup

    position_id = decoded["position_id"]
    if position_id.present?
      if position_id.is_a?(Array)
        old_id, new_id = position_id
        decoded["position_id"] = [
          { "id" => old_id, "title" => Position.find_by(id: old_id)&.title },
          { "id" => new_id, "title" => Position.find_by(id: new_id)&.title }
        ]
      else
        decoded["position_title"] = Position.find_by(id: position_id)&.title
      end
    end

    slot_id = decoded["slot_id"]
    if slot_id.is_a?(Array)
      decoded["slot_id"] = slot_id.map { |id| id && { "id" => id, "description" => slot_description(id) } }
    end

    forced = decoded["forced"]
    return decoded if forced == true

    if forced.present?
      # Old blocker format -- convert to new
      reason = Timesheet::OLD_BLOCKERS[forced["reason"]] || "unknown"
      blocker = { "blocker" => reason }

      blocker["within_years"] = 5 if reason == Timesheet::BLOCKED_NO_BURN_PERIMETER_EXP

      if forced["position_id"].present?
        blocker["position"] = {
          "id" => forced["position_id"],
          "title" => Position.find_by(id: forced["position_id"])&.title
        }
      end

      decoded["forced"] = true
      decoded["blockers"] = [blocker]
    end

    decoded
  end

  private

  # A shift as it reads in a log line. Falls back to the id when the shift has
  # been deleted or was never given a description.
  def slot_description(slot_id)
    Slot.where(id: slot_id).pick(:description).presence || "Shift ##{slot_id}"
  end
end
