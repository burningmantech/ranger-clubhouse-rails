# frozen_string_literal: true

# Saves a Missing Timesheet request and, when the request is approved with
# "create entry" checked, creates the timesheet entry in the same transaction:
# the new entry is logged as created via the missing-entry request, the
# request's notes are copied over, admin notes cross-referencing the two
# records are added, and a confirmed current-year timesheet is un-confirmed.
#
# Port of the Laravel TimesheetMissingController#saveAndMaybeCreateNewEntry.
module TimesheetMissingReview
  class << self
    # @param entry [TimesheetMissing] the request, with pending attribute changes
    # @param person [Person] the person the request is for
    # @param reviewer_id [Integer] the person performing the save
    # @return [Boolean] false when validation failed — errors are on +entry+
    def save_and_maybe_create_entry(entry, person, reviewer_id)
      was_persisted = entry.persisted?
      create_new = entry.status_approved? && entry.create_entry

      if create_new && !PersonPosition.have_position?(person.id, target_position_id(entry, was_persisted))
        entry.errors.add(:new_position_id, "The position is not held by #{person.callsign}.")
        return false
      end

      success = false
      ActiveRecord::Base.transaction do
        raise ActiveRecord::Rollback unless save_request(entry, was_persisted)

        if create_new
          timesheet = build_timesheet(entry, person, was_persisted)
          raise ActiveRecord::Rollback unless save_timesheet(timesheet, entry)

          record_creation(entry, timesheet, reviewer_id)
          unconfirm_timesheet(timesheet, person, reviewer_id)
        end

        success = true
      end

      success
    end

    private

    def target_position_id(entry, was_persisted)
      was_persisted && entry.new_position_id.present? ? entry.new_position_id : entry.position_id
    end

    # The model's additional_notes validation enforces the self-serve rule (a
    # requester note is always required). On the review side a new request
    # needs a requester OR wrangler note, and a review update needs none.
    def save_request(entry, was_persisted)
      require_requester_note = !was_persisted && entry.additional_wrangler_notes.blank?
      entry.valid?
      entry.errors.delete(:additional_notes) unless require_requester_note
      return false if entry.errors.any?

      entry.save(validate: false)
    end

    def build_timesheet(entry, person, was_persisted)
      timesheet = Timesheet.new(
        person_id: person.id,
        on_duty: was_persisted ? entry.new_on_duty : entry.on_duty,
        off_duty: was_persisted ? entry.new_off_duty : entry.off_duty,
        position_id: target_position_id(entry, was_persisted)
      )
      timesheet.audit_reason = "created via missing timesheet request"
      timesheet
    end

    # The timesheet's additional_notes validation does not apply here — the
    # request's notes are copied onto the new entry instead.
    def save_timesheet(timesheet, entry)
      timesheet.valid?
      timesheet.errors.delete(:additional_notes)

      if timesheet.errors.any?
        timesheet.errors.full_messages.each { |message| entry.errors.add(:base, "New entry: #{message}") }
        return false
      end

      timesheet.save(validate: false)
    end

    def record_creation(entry, timesheet, reviewer_id)
      timesheet.log(TimesheetLog::CREATED, {
                      via: TimesheetLog::VIA_MISSING_ENTRY,
                      position_id: timesheet.position_id,
                      on_duty: timesheet.on_duty.to_s,
                      off_duty: timesheet.off_duty.to_s
                    })

      copy_notes(entry, timesheet)

      TimesheetMissingNote.record(entry.id, reviewer_id, "Timesheet ##{timesheet.id} created.",
                                  TimesheetMissingNote::TYPE_ADMIN)
      TimesheetNote.record(timesheet.id, reviewer_id, "Timesheet created from Missing Timesheet Request.",
                           TimesheetNote::TYPE_ADMIN)
    end

    # Copy all of the request's notes onto the new entry, preserving the
    # original authors and times.
    def copy_notes(entry, timesheet)
      entry.timesheet_missing_notes.order(:created_at).each do |note|
        TimesheetNote.create!(
          timesheet_id: timesheet.id,
          type: note.type,
          note: "[copied from Missing Timesheet request]\n#{note.note}",
          create_person_id: note.create_person_id,
          created_at: note.created_at
        )
      end
    end

    def unconfirm_timesheet(timesheet, person, reviewer_id)
      year = timesheet.on_duty.year
      return unless year == Current.year
      return unless TimesheetManagement.set_confirmed_flag(person.id, year, false,
                                                           audit_reason: "unconfirmed - new (missing) entry created")

      TimesheetLog.record(TimesheetLog::UNCONFIRMED, person.id, reviewer_id, nil,
                          "new entry (from missing request) created.")
    end
  end
end
