# frozen_string_literal: true

# The completed training report (Ember training/people-training-completed).
# Read-only; resolution, the TrainingPolicy view gate, and @year come from
# the base controller.
#
# Upstream put every session's roster behind an accordion on one page. Here
# the index is the summary table and each session gets its own page, which
# is what makes the rosters linkable and printable.
class Training::CompletedTrainingController < Training::BaseController
  include CsvExportConcern

  before_action :load_report
  # Not the base controller's load_session -- that one builds a TrainingSession
  # for the management pages. This report only needs its own report entry.
  before_action :load_report_session, only: :show

  def index
    respond_to do |format|
      format.html
      format.csv do
        send_csv(csv_rows, filename: "#{@year}-#{training_slug}-completed-training.csv")
      end
    end
  end

  def show
  end

  private

  # The show page's pager walks the same ordered session list the index
  # renders, so both actions build the whole report.
  def load_report
    @report = Training::CompletedReport.execute(@training, @year)
  end

  def load_report_session
    index = @report.sessions.index { |session| session.slot.id == params[:slot_id].to_i }

    unless index
      redirect_to training_completed_training_path(training_slug, year: @year),
                  error: "Training session not found."
      return
    end

    @session = @report.sessions[index]
    @previous_session = index.positive? ? @report.sessions[index - 1] : nil
    @next_session = @report.sessions[index + 1]
  end

  # Upstream's export: trainees only, never trainers, one row per pass.
  # Dates stay spreadsheet-sortable -- slot.begins is already the session's
  # local wall-clock time, so no begins_adjusted conversion.
  def csv_rows
    show_email = Current.can_view_email?
    header = ["Session", "Location", "Callsign"]
    header << "Email" if show_email

    @report.sessions.each_with_object([header]) do |session, rows|
      slot = session.slot
      session.trainees.each do |person|
        row = [slot.begins.strftime(DateTimeHelper::CSV_TIME), slot.description, person.callsign]
        row << person.email if show_email
        rows << row
      end
    end
  end
end
