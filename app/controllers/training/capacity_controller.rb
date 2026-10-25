# frozen_string_literal: true

# The training capacity report page (Ember training/capacity). Read-only;
# resolution, the TrainingPolicy view gate, and @year come from the base
# controller.
class Training::CapacityController < Training::BaseController
  include CsvExportConcern

  CSV_HEADER = ["Training", "Date", "Timezone", "% Filled", "Seats", "Signed Up", "PNVs", "Returning",
                "Auditors", "Passed", "Not Passed", "Trainers"].freeze

  def index
    @report = Training::CapacityReport.execute(@training, @year)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{@year}-#{training_slug}-capacity.csv") }
    end
  end

  private

  # Upstream's column set and totals row; dates stay spreadsheet-sortable
  # (the page renders the house shift format instead). Pass columns are
  # blank until the session has ended -- same dash rule as the page.
  #
  # slot.begins is already the session's LOCAL wall-clock time -- the page
  # stamps the zone onto it rather than converting (DateTimeHelper's
  # parse_time_in_zone). Slot#begins_adjusted converts instead, which shifts
  # any session outside the app zone: a Green Dot session in MDT lands an hour
  # late, one in BST eight hours out. Hence the raw strftime, plus a Timezone
  # column so two sessions in different zones can actually be compared.
  def csv_rows
    rows = [CSV_HEADER]

    @report.rows.each do |row|
      slot = row.slot
      scored = row.scored
      rows << [slot.description,
               slot.begins.strftime(DateTimeHelper::CSV_TIME),
               slot.timezone_abbr,
               "#{row.filled}%",
               slot.max,
               row.signed_up,
               row.pnv_count,
               row.veteran_count,
               row.auditor_count,
               scored ? row.passed : "",
               scored ? row.not_passed : "",
               row.trainer_count]
    end

    totals = @report.totals
    rows << ["", "Totals", "", "#{totals.filled}%", totals.max, totals.signed_up,
             totals.pnv_count, totals.veteran_count, totals.auditor_count,
             totals.passed, totals.not_passed, "#{@report.unique_trainers} (unique)"]
    rows
  end
end
