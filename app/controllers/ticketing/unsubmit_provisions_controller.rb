# frozen_string_literal: true

# Recommends whose earned provisions to un-submit after the event (Ember
# vc/access-documents/unsubmit-provisions port): people who claimed or
# submitted provisions but did not ranger that year. The operator reviews the
# checkbox table, picks people, and the commit returns their provisions to
# available.
#
# The commit renders its ledger with a 422 for the same reason the maintenance
# tasks do: the results are transient and Turbo drops a 200 form response.
class Ticketing::UnsubmitProvisionsController < ApplicationController
  include CsvExportConcern

  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to run ticketing maintenance."

  CSV_HEADER = ["Callsign", "Status", "Ticket", "SAP?", "BMID Printed?", "Sign-Ups?", "Provisions"].freeze

  def index
    @year = TicketingMaintenance.maintenance_year
    @rows = UnsubmitProvisionsReport.execute(@year)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{@year}-unsubmit-provisions.csv") }
    end
  end

  def commit
    person_ids = IdList.parse(params.permit(person_ids: [])[:person_ids])

    if person_ids.empty?
      return redirect_to ticketing_unsubmit_provisions_path,
                         alert: "Select at least one person to un-submit."
    end

    @rows = TicketingMaintenance::UnsubmitProvisions.unsubmit(person_ids)
    render :results, status: :unprocessable_entity
  end

  private

  # Cell strings come from the report Row so the CSV and the table can never
  # disagree.
  def csv_rows
    rows = [CSV_HEADER]

    @rows.each do |row|
      rows << [
        row.person.callsign,
        row.person.status,
        row.ticket_summary || "",
        csv_yes_no(row.has_sap),
        csv_yes_no(row.bmid),
        csv_yes_no(row.signed_up),
        row.provision_summaries.join("; ")
      ]
    end

    rows
  end
end
