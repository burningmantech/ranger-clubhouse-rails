# frozen_string_literal: true

# Rangers who look like they still need a Setup Access Pass
# (Ember vc/access-documents/waps port).
#
# Upstream drew one table and nothing else. Here the two reasons a person lands
# on the list — they hold a ticket, or they have signed up with nothing on file
# — are a pair of header counts, and the sign-up detail folds away so a long
# schedule cannot push the rest of the row off screen.
class Ticketing::SapCandidatesController < ApplicationController
  include CsvExportConcern

  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to view ticketing reports."

  CSV_HEADER = ["Callsign", "Status", "Email", "Has SPT?", "Years With Shifts", "Sign Ups"].freeze

  def index
    @start_year = SapCandidatesReport.start_year(Current.year)
    # One read feeds the counts, the table, and the CSV, so an export can never
    # disagree with the table it was taken from.
    @rows = SapCandidatesReport.execute(Current.year)
    @total_count = @rows.size
    @with_ticket_count = @rows.count(&:has_spt)
    @signed_up_count = @total_count - @with_ticket_count

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{Current.year}-sap-candidates.csv") }
    end
  end

  private

  def csv_rows
    rows = [CSV_HEADER]

    @rows.each do |row|
      rows << [
        row.person.callsign,
        row.person.status,
        row.person.email,
        row.has_spt ? row.tickets.map { |ticket| ticket_summary(ticket) }.join("; ") : "NO SPT",
        row.years.join(", "),
        row.schedule.map { |signup| "#{signup.begins_label} #{signup.position_title} #{signup.description}".squish }
                    .join("; ")
      ]
    end

    rows
  end

  # The same "RAD-123 SPT qualified" shorthand the table shows.
  def ticket_summary(ticket)
    "#{ticket.display_ref} #{ticket.short_type_label} #{ticket.status}"
  end
end
