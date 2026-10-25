# frozen_string_literal: true

# People signed up for a paid shift in the year whose Paycom Employee ID is
# missing, or set to the "0" that clears them to take it unpaid.
class ShiftOperations::PayrollMissingIdController < ApplicationController
  include CsvExportConcern

  layout "shift_operations"

  authorize_role [Role::ADMIN, Role::PAYROLL],
                 message: "Payroll role required to view people missing a Paycom Employee ID."

  # Paycodes and Paycom Employee IDs were first recorded in 2023. Before then,
  # every year would list everyone signed up for a position paid today.
  self.year_floor = 2023

  CSV_HEADER = ["Callsign", "First Name", "Last Name", "Status", "Paycom Employee ID",
                "Paid Positions", "Paid Shifts", "First Paid Shift"].freeze

  before_action :setup_year

  def index
    @report = PayrollMissingIdReport.execute(@year)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{@year}-payroll-missing-id.csv") }
    end
  end

  private

  # The page's order: the missing, then the 0s. The id column is what tells
  # them apart here -- blank or 0.
  def csv_rows
    [CSV_HEADER] + (@report.missing + @report.unpaid).map { |row|
      person = row.person
      [person.callsign, person.first_name, person.last_name, person.status,
       person.employee_id, row.positions_text, row.sign_ups.size,
       row.first_slot.begins.strftime(DateTimeHelper::CSV_TIME)]
    }
  end
end
