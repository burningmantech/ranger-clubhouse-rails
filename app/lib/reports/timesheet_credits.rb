# frozen_string_literal: true

# What a timesheet row is worth, priced in one pass over the year's credits.
#
# Lives apart from TimesheetYearReport because pricing a row and deciding which
# rows a reader may see are separate questions. Timesheets by Callsign and
# Timesheet by Position need both and reach this through that concern; a report
# gated whole-page by role needs only this, and including the visibility
# concern to reach the arithmetic implied it honoured a scoping rule it does
# not.
#
# Timesheet#credits and TimesheetMissing#credits read the year's whole credit
# cache on every call, and the dev/prod stores hand back a fresh deserialized
# copy each time -- 5,600 entries took 79 seconds and nine of them in GC. This
# reads each year's credits once.
module TimesheetCredits
  # What PositionCredit.bulk_compute_credits needs: a position, two integer
  # timestamps, and somewhere to put the answer. Neither Timesheet nor
  # TimesheetMissing has a credits column, and so neither has a writer, which
  # is why the calculation cannot be run over the records themselves.
  CreditRow = Struct.new(:position, :starts, :ends, :credits)

  class << self
    # {row id => credits} for one collection of rows.
    def credits_by_id(rows) = credits_by_collection(rows).first

    # One {row id => credits} per collection, in the order given.
    #
    # The hashes stay apart on purpose: ids from two tables are drawn from
    # different sequences and collide freely, so a merged hash would price one
    # row with the other's credits.
    def credits_by_collection(*collections)
      collections.map { |rows| price(rows) }
    end

    private

    # Grouped by each row's OWN year rather than any report's, as
    # Timesheet#credits is. for_year compares the stored wall clock while the
    # value read back is cast into Time.zone, so a New Year's Eve entry can sit
    # in one year's scope and belong to the next year's credit table -- and
    # pricing it by the report year would show different credits than
    # /person/:id/timesheets does.
    #
    # A row whose position is gone is priced at zero: the Laravel-shared schema
    # carries no FK, so position reads nil even though the association is not
    # optional.
    def price(rows)
      priced, unpriced = rows.partition(&:position)
      credits = {}

      priced.group_by { |row| row.on_duty.year }.each do |year, group|
        credit_rows = group.map do |row|
          CreditRow.new(row.position, row.on_duty.to_i, (row.off_duty || Current.time).to_i)
        end
        PositionCredit.bulk_compute_credits(credit_rows, credit_rows, year, :starts, :ends)
        group.each_with_index { |row, idx| credits[row.id] = credit_rows[idx].credits }
      end

      unpriced.each { |row| credits[row.id] = 0.0 }
      credits
    end
  end
end
