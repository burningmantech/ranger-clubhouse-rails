# frozen_string_literal: true

# Freaking Years: every Active Ranger's total service years.
#
# No query is built here beyond a single pluck. years_of_service is already
# materialised on person by YearsManagement (app/lib/years_management.rb) --
# ranger, award, and contributor years combined -- and is the same column
# upstream's ServiceYearsReport reads, so this page and a person's profile can
# never disagree.
#
# Deliberately NOT year-scoped: service is all-time.
class FreakingYearsReport
  # Plain value rows, not Person records: nothing on the page needs an
  # association.
  Row = Data.define(:id, :callsign, :first_name, :last_name,
                    :years, :first_year, :last_year) do
    def name = "#{first_name} #{last_name}".strip
  end

  # Active only, as upstream. Someone with no service years yet is kept, again
  # as upstream: the total is the whole Active roster, and #first_year and
  # #last_year are nil for them.
  #
  # @return [Array<Row>] longest service first, then callsign. Upstream meant
  #   the same -- its tiebreak compares years to years, so it never fires.
  def self.execute
    Person.where(status: Person::ACTIVE)
          .pluck(:id, :callsign, :first_name, :preferred_name, :last_name, :years_of_service)
          .map { |id, callsign, first, preferred, last, service|
            # The upstream Laravel app writes this table too, so a JSON scalar
            # or object counts as no service rather than raising.
            years = service.is_a?(Array) ? service : []
            first_year, last_year = years.minmax

            # first_name mirrors Person#desired_first_name.
            Row.new(id:, callsign:, last_name: last.to_s,
                    first_name: preferred.presence || first.to_s,
                    years: years.size, first_year:, last_year:)
          }
          .sort_by { |row| [-row.years, row.callsign.to_s.downcase] }
  end
end
