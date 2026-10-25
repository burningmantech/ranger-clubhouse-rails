# frozen_string_literal: true

# Unclaimed tickets, each flagged with whether its holder has already signed up
# for a late-season shift.
#
# An unclaimed ticket is a special price ticket or staff credential still sitting
# at "qualified" — earned, but never claimed. A sign-up for a shift starting on
# or after the cutoff means the person is almost certainly coming, so the pairing
# of "signed up" with "never claimed" is the row worth chasing.
class UnclaimedTicketsWithSignupsReport
  Row = Data.define(:document, :has_signup) do
    def person
      document.person
    end
  end

  # The earliest shift start that counts as a sign-up: August 15th. Upstream
  # hardcoded that date twice — once in the API report and again in the Ember
  # template's prose — where the two could silently drift apart. The page
  # renders it from here, so there is only one to change.
  #
  # Built with Time.local rather than Time.zone: slot.begins is stored in
  # system-local time, so a zoned boundary lands an hour off and would drag the
  # previous evening's shifts in.
  #
  # @param year [Integer]
  # @return [Time]
  def self.signup_cutoff(year)
    Time.local(year, 8, 15)
  end

  # @param year [Integer]
  # @return [Array<Row>] sorted by callsign, case-insensitively
  def self.execute(year)
    # Documents whose person has since been deleted are dropped rather than
    # rendered as a blank row.
    documents = AccessDocument.where(type: AccessDocument::REGULAR_TICKET_TYPES,
                                     status: AccessDocument::QUALIFIED)
                              .includes(:person)
                              .to_a
                              .select(&:person)

    signed_up = PersonSlot.joins(:slot)
                          .where(person_id: documents.map(&:person_id).uniq)
                          .where(slot: { begins_year: year, begins: signup_cutoff(year).. })
                          .distinct
                          .pluck(:person_id)
                          .to_set

    documents.map { |document| Row.new(document:, has_signup: signed_up.include?(document.person_id)) }
             .sort_by { |row| row.person.callsign.downcase }
  end
end
