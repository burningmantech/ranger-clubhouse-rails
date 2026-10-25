# frozen_string_literal: true

# Spigot Flow report: day-by-day counts of Prospectives reaching intake milestones.
class Vc::SpigotFlowReportController < ApplicationController
  include CsvExportConcern

  layout "vc"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to view the Spigot Flow report."

  # Export labels match the upstream Ember CSV, keyed by stage so the columns
  # can never drift out of order with SpigotFlowReport::STAGES.
  CSV_LABELS = {
    imported: "Imported",
    created: "Created",
    first_login: "First Login",
    photo_approved: "BMID Photo Approved",
    online_trained: "Online Trained",
    training_signups: "Sign Up For Training",
    training_passed: "Trained",
    dropped: "Dropped",
    alpha_signups: "Alpha Sign Up"
  }.freeze

  def index
    setup_year
    @days = SpigotFlowReport.execute(@year)
    @totals = SpigotFlowReport::STAGES.index_with { |stage| @days.sum { |day| day[stage]&.size.to_i } }

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{@year}-spigot-flow.csv") }
    end
  end

  private

  # Counts only, matching the upstream export — the CSV never includes callsigns.
  def csv_rows
    rows = [["Date", *SpigotFlowReport::STAGES.map { |stage| CSV_LABELS.fetch(stage) }]]
    @days.each do |day|
      date = day[:day] == SpigotFlowReport::PREVIOUS_YEAR_KEY ? "Prev. Year" : day[:day]
      rows << [date, *SpigotFlowReport::STAGES.map { |stage| day[stage]&.size }]
    end
    rows
  end
end
