# frozen_string_literal: true

# The trainer attendance report page (Ember training/:position_id/
# trainer-attendance). Read-only; resolution, the TrainingPolicy view gate, and
# @year come from the base controller.
class Training::TrainerAttendanceController < Training::BaseController
  include CsvExportConcern

  CSV_HEADER = ["Callsign", "Date", "Timezone", "Type", "Description", "Attended"].freeze

  def index
    @report = Training::TrainerAttendanceReport.execute(@training, @year)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{@year}-#{training_slug}-trainer-attendance.csv") }
    end
  end

  private

  # Upstream's column set; dates stay spreadsheet-sortable (the page renders
  # the house shift format instead). slot.begins is already the session's LOCAL
  # wall-clock time, so it is stamped with its zone rather than converted --
  # Slot#begins_adjusted would shift any session outside the app zone. Hence
  # the raw strftime plus a Timezone column.
  def csv_rows
    rows = [CSV_HEADER]

    @report.trainers.each do |trainer|
      trainer.rows.each do |row|
        rows << [trainer.callsign,
                 row.slot.begins.strftime(DateTimeHelper::CSV_TIME),
                 row.slot.timezone_abbr,
                 row.position_title,
                 row.slot.description,
                 row.status]
      end
    end
    rows
  end
end
