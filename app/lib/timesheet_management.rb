# frozen_string_literal: true

# Timesheet Management module
# Handles timesheet confirmation status and sign-in reporting
module TimesheetManagement
  class << self
    # Unconfirm the entire timesheet
    #
    # Only unconfirms a timesheet if it's for the current year
    #
    # @param timesheet [Timesheet] The timesheet entry to unconfirm
    # @param reason [String] The reason for unconfirming
    # @return [void]
    def unconfirm_timesheet(timesheet, reason)
      year = timesheet.on_duty.year

      # Only unconfirm a timesheet if it's the current year.
      return unless year == Current.year
      return unless set_confirmed_flag(timesheet.person_id, year, false)

      timesheet.log(TimesheetLog::UNCONFIRMED, "timesheet ##{timesheet.id} #{reason}")
    end

    # Set the person's timesheet-confirmed flag for a year. Callers record
    # their own audit log rows.
    #
    # @return [Boolean] false when the flag was already in the requested state
    def set_confirmed_flag(person_id, year, confirmed, audit_reason: nil)
      event = PersonEvent.first_or_new_for_person_year(person_id, year)
      return false if !!event.timesheet_confirmed == confirmed

      event.audit_reason = audit_reason if audit_reason
      event.timesheet_confirmed = confirmed
      event.timesheet_confirmed_at = confirmed ? Current.time : nil
      event.save(validate: false)
      true
    end

    # Build response data for a timesheet sign-in or creation.
    #
    # @param action [String] The action being logged
    # @param timesheet [Timesheet] The timesheet entry
    # @param sign_in_forced [Boolean] Whether the sign-in was forced
    # @param blockers [Array<Hash>] List of blockers that were overridden
    # @param log [Hash] Additional log data
    # @return [Hash] Response hash containing status and timesheet details
    def report_sign_in(action, timesheet, sign_in_forced, blockers, log)
      response = {
        status: "success",
        timesheet_id: timesheet.id,
        on_duty: timesheet.on_duty.to_s,
        slot_info: timesheet.slot&.url,
        position_title: timesheet.position.title
      }

      if sign_in_forced
        response[:forced] = true
        log[:forced] = true
        log[:blockers] = blockers
      end

      timesheet.log(action, log)

      response
    end
  end
end
