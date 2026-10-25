# frozen_string_literal: true

# Tickets that run out at the end of the coming event.
#
# A ticket earned in one year stays good for a few more, then lapses. This
# gathers the special price tickets and staff credentials whose time is up: the
# ones still sitting at "qualified" (earned, never claimed) and the ones
# deliberately parked at "banked". Both lapse on the same date, and a banked
# ticket about to lapse is the more urgent of the two — its holder thinks it is
# safe.
class ExpiringTicketsReport
  # A ticket whose expiry_date already fell in an earlier year is stale data
  # rather than someone to chase, so the flag rides along with the row.
  Row = Data.define(:document, :expired) do
    def person
      document.person
    end
  end

  STATUSES = [AccessDocument::QUALIFIED, AccessDocument::BANKED].freeze

  # @param year [Integer]
  # @return [Array<Row>] sorted by callsign (case-insensitively), then by the
  #   year the ticket was earned
  def self.execute(year)
    # expiry_date is a date column, so a plain range gives "expires during this
    # year or earlier" and can still use an index — YEAR(expiry_date) could not.
    # Tickets with no expiry date are excluded by the comparison, as upstream.
    AccessDocument.where(type: AccessDocument::REGULAR_TICKET_TYPES,
                         status: STATUSES,
                         expiry_date: ..Date.new(year, 12, 31))
                  .includes(:person)
                  .to_a
                  # A document whose person has since been deleted is dropped
                  # rather than rendered as a blank row.
                  .select(&:person)
                  .map { |document| Row.new(document:, expired: document.expiry_date.year < year) }
                  .sort_by { |row| [row.person.callsign.downcase, row.document.source_year.to_i] }
  end
end
