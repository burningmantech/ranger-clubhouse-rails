# frozen_string_literal: true

# Rangers who have not confirmed their timesheet is correct (Ember
# reports/timesheet-unconfirmed port, upstream
# app/Lib/Reports/PeopleWithUnconfirmedTimesheetsReport.php).
#
# Membership is decided by the confirmation flag alone: an active person who
# turned in hours this year and has not set person_event.timesheet_confirmed.
# The unverified count rides along and is allowed to be zero -- someone whose
# entries are all verified but who never clicked the final confirmation is
# exactly who this report exists to find.
class UnconfirmedTimesheetsReport
  Row = Data.define(:person, :unverified_count) do
    def needs_verifying? = unverified_count.positive?

    def name = person.desired_full_name
  end

  # An entry whose review is still open: unverified, or rejected and back with
  # the ranger to answer. Deliberately NOT
  # Timesheet.count_unverified_for_person_year, which counts every status
  # except verified -- approved and pending too -- and drops entries still on
  # duty. Same name, different question.
  OPEN_REVIEW = [Timesheet::STATUS_UNVERIFIED, Timesheet::STATUS_REJECTED].freeze

  class << self
    # @param year [Integer]
    # @return [Array<Row>] callsign order
    def execute(year:)
      people = people(year).to_a
      return [] if people.empty?

      # Counted over the roster, not the whole year: everyone who already
      # confirmed, and everyone whose status keeps them off the report, would
      # otherwise be aggregated and then thrown away.
      counts = Timesheet.for_year(year)
                        .where(person_id: people.map(&:id), review_status: OPEN_REVIEW)
                        .group(:person_id).count

      people.map { |person| Row.new(person:, unverified_count: counts[person.id].to_i) }
    end

    # The chase list for one group of rows. Addresses are optional on Person, so
    # a group can be non-empty and still have nothing to copy.
    # @param rows [Array<Row>]
    # @return [Array<String>]
    def emails(rows) = rows.filter_map { |row| row.person.email.presence }.uniq

    private

    # Both subqueries select a NOT NULL column, so the NOT IN cannot be
    # emptied by a NULL row. distinct on the first: it asks "who turned in
    # hours", and without it the subquery hands over one row per timesheet.
    def people(year)
      Person.active
            .where(id: Timesheet.for_year(year).distinct.select(:person_id))
            .where.not(id: PersonEvent.where(year:, timesheet_confirmed: true).select(:person_id))
            .order(:callsign)
            .select(:id, :callsign, :first_name, :preferred_name, :last_name,
                    :email, :home_phone)
    end
  end
end
