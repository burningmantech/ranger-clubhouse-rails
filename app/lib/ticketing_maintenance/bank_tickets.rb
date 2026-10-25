# frozen_string_literal: true

module TicketingMaintenance
  # Post-event: carry all qualified tickets forward as banked, deliberately
  # without checking expiration (that is Expire Tickets' job), and scrub the
  # access date off banked Staff Credentials -- the date belongs to the event
  # that just ended. Port of the Laravel
  # AccessDocumentController#bankAccessDocuments, including its second pass
  # over previously banked Staff Credentials still carrying a date.
  #
  # The two selections never overlap, even in a preview where nothing saves:
  # pass one matches qualified rows and clears their dates while banking, so
  # pass two's banked-with-a-date query cannot see them.
  class BankTickets < Base
    def self.title = "Bank Tickets From Prior Event"

    def self.description
      "Mark all qualified tickets and credentials as banked without checking expiration, " \
        "and clear access dates left on banked Staff Credentials."
    end

    def self.bank_scope
      AccessDocument.where(status: AccessDocument::QUALIFIED, type: AccessDocument::TICKET_TYPES)
    end

    def self.scrub_scope
      AccessDocument.where(status: AccessDocument::BANKED, type: AccessDocument::STAFF_CREDENTIAL)
                    .where.not(access_date: nil).or(
                      AccessDocument.where(status: AccessDocument::BANKED,
                                           type: AccessDocument::STAFF_CREDENTIAL, access_any_time: true))
    end

    def execute
      sorted(bank_rows + scrub_rows)
    end

    private

    def bank_rows
      self.class.bank_scope.includes(:person).map do |document|
        detail = "access date cleared" if document.staff_credential? && clear_access_date(document)
        status_row(document, to: AccessDocument::BANKED, detail:,
                   comment: "marked as banked via maintenance function",
                   audit_reason: "maintenance - bank tickets")
      end
    end

    def scrub_rows
      self.class.scrub_scope.includes(:person).map do |document|
        clear_access_date(document)
        save_row(document, change: "access date → unspecified",
                 comment: "set access date to unspecified via maintenance function",
                 audit_reason: "maintenance - bank tickets")
      end
    end

    # True when there was anything to clear.
    def clear_access_date(document)
      had_date = document.access_date.present? || document.access_any_time?
      document.access_date = nil
      document.access_any_time = false
      had_date
    end
  end
end
