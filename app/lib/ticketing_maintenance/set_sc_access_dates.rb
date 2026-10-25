# frozen_string_literal: true

module TicketingMaintenance
  # Give every live Staff Credential without a current-year access date the
  # default access date. Port of the Laravel
  # AccessDocumentController#setStaffCredentialsAccessDate.
  #
  # Upstream silently skipped dismissed and deceased holders; here they appear
  # in the ledger as unchanged so the preview explains itself.
  class SetScAccessDates < Base
    def self.title = "Set Staff Credential Access Dates"

    def self.description
      "Set the default access date on all qualified, claimed, or banked Staff Credentials " \
        "that are missing one."
    end

    def self.access_date = Setting.get_value(Setting::TAS_DEFAULT_SAP_DATE)

    def self.blocked_reason
      return if access_date.present?

      "The #{Setting::TAS_DEFAULT_SAP_DATE} setting (default SAP access date) is blank. " \
        "Set it before assigning access dates."
    end

    def self.card_note = "Default access date: #{access_date}"

    # Missing means blank or left over from another year. The year test is a
    # local-time range: access dates are stored as machine-local wall clock, so
    # a zoned boundary or YEAR() lands an hour off (and YEAR() cannot use an
    # index).
    def self.scope
      base = AccessDocument.where(type: AccessDocument::STAFF_CREDENTIAL,
                                  status: AccessDocument::ACTIVE_STATUSES, access_any_time: false)
      this_year = Time.local(Current.year)...Time.local(Current.year + 1)
      base.where(access_date: nil).or(base.where.not(access_date: this_year))
    end

    def execute
      access_date = self.class.access_date

      walk do |document|
        if TicketingManagement::EXCLUDED_HOLDER_STATUSES.include?(document.person&.status)
          next skip_row(document, detail: "person is #{document.person.status}")
        end

        change = "access date #{document.access_date&.to_date || 'none'} → #{access_date}"
        document.access_date = access_date
        save_row(document, change:,
                 comment: "changed access date to #{access_date} via maintenance function",
                 audit_reason: "maintenance - set staff credential access date")
      end
    end
  end
end
