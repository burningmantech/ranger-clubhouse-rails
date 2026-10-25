# frozen_string_literal: true

# Shiny Penny report: who passed training and mentoring in a given year.
class Vc::ShinyPennyReportController < ApplicationController
  include CsvExportConcern

  layout "vc"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to view the Shiny Penny report."

  def index
    setup_year
    @people = ShinyPennyReport.execute(@year)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{@year}-shiny-pennies.csv") }
    end
  end

  private

  # Column order matches the upstream Ember export.
  def csv_rows
    [["Callsign", "Status", "Email", "First Name", "Last Name"]] +
      @people.map { |person| [person.callsign, person.status, person.email, person.desired_first_name, person.last_name] }
  end
end
