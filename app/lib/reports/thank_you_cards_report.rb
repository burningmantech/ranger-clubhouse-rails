# frozen_string_literal: true

# Who should receive a Thank You card for a given year: everyone who rangered
# at least one shift, minus the statuses the department does not mail to.
class ThankYouCardsReport
  # Applicants have not finished becoming Rangers and auditors are only
  # visiting, so neither is owed a card. No one can ask for these back.
  ALWAYS_SKIPPED_STATUSES = [
    Person::ALPHA,
    Person::AUDITOR,
    Person::BONKED,
    Person::PAST_PROSPECTIVE,
    Person::PROSPECTIVE,
    Person::SUSPENDED,
    Person::UBERBONKED
  ].freeze

  # People the department does not mail, left out unless the reader asks for
  # them. Someone checking who the list misses can put them back.
  OPTIONAL_STATUSES = [
    Person::DECEASED,
    Person::DISMISSED,
    Person::RESIGNED
  ].freeze

  # Only what the page and the export read. A person row carries a password
  # hash and several long text columns this list has no use for.
  COLUMNS = %i[id callsign first_name last_name status email
               street1 street2 apt city state zip country bpguid].freeze

  # @param year [Integer]
  # @param include_statuses [Array<String>] any of OPTIONAL_STATUSES to add back
  # @return [ActiveRecord::Relation<Person>] sorted by callsign
  def self.execute(year, include_statuses: [])
    skipped = ALWAYS_SKIPPED_STATUSES + (OPTIONAL_STATUSES - Array(include_statuses))

    Person.where.not(status: skipped)
          .where(id: Timesheet.for_year(year).select(:person_id))
          .order(:callsign)
          .select(*COLUMNS)
  end
end
