# frozen_string_literal: true

# Events Rangered: a service census. One row per person who has rangered at
# least one year -- how many years, the first and last of them, and whether
# they have signed up for anything this event.
#
# No query is built here beyond a single pluck. Both year lists are already
# materialised on person by YearsManagement (app/lib/years_management.rb),
# which recomputes them from Timesheet and PersonSlot callbacks.
#
# Deliberately NOT year-scoped: the census is all-time. Only #signed_up carries
# a year, and the caller passes it.
#
# The years count comes from person.years_as_ranger rather than upstream's
# report-local SQL, so this page and a person's profile can never disagree.
# That is a knowing divergence from the Ember report, which counts distinct
# timesheet years excluding Alpha and HQ Runner: years_as_ranger excludes
# Training instead, allows Alpha years only for people who passed mentoring
# from 2025, and requires six hours in a year from 2025 onward
# (Timesheet.compute_years_for_person). The totals do not match upstream's and
# are not meant to. Note the six-hour rule also moves #first_year/#last_year:
# a year under the floor is absent from the list those are taken from.
class EventsRangeredReport
  # Plain value rows, not Person records: the unfiltered census is thousands of
  # people and nothing on the page needs an association.
  Row = Data.define(:id, :callsign, :first_name, :last_name, :status,
                    :years, :first_year, :last_year, :signed_up) do
    def name = "#{first_name} #{last_name}".strip
  end

  # @param year [Integer] the event year the Signed Up column asks about
  # @return [Array<Row>] years descending, then callsign ascending
  def self.execute(year)
    Person.pluck(:id, :callsign, :first_name, :preferred_name, :last_name,
                 :status, :years_as_ranger, :years_of_signups)
          .filter_map { |id, callsign, first, preferred, last, status, ranger, signups|
            # Both columns are JSON text on a table the upstream Laravel app
            # also writes, and MariaDB's json_valid() admits scalars and
            # objects, so a malformed row is skipped rather than left to raise
            # and take the whole census down with it.
            years = ranger.is_a?(Array) ? ranger : []
            # Someone who has never rangered has no service to report. Upstream's
            # query cannot produce a zero-years row either.
            next if years.empty?

            # first_name mirrors Person#desired_first_name. years_as_ranger is
            # stored ascending, but min/max says so out loud and costs nothing
            # at this size.
            Row.new(id:, callsign:, status:, last_name: last.to_s,
                    first_name: preferred.presence || first.to_s,
                    years: years.size, first_year: years.min, last_year: years.max,
                    signed_up: signups.is_a?(Array) && signups.include?(year))
          }
          .sort_by { |row| [-row.years, row.callsign.to_s.downcase] }
  end

  # The service-length roll-up shown above the roster. Built from the same rows
  # the roster draws from, so a bar and its people can never disagree.
  #
  # The roll-up itself, including the :matching contract, is RosterRollup's --
  # see it for what each count means.
  #
  # @param rows [Array<Row>]
  # @return [Array<Hash>] { years:, people:, signed_up:, matching: }, longest
  #   service first
  def self.distribution(rows, &matching)
    RosterRollup.by(rows, :years, &matching)
  end
end
