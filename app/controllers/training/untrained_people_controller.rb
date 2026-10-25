# frozen_string_literal: true

# The untrained-people report page (Ember training/:position_id/
# untrained-people). Read-only; resolution, the TrainingPolicy view gate, and
# @year come from the base controller -- upstream's untrainedPeopleReport
# policy is the same canView rule.
class Training::UntrainedPeopleController < Training::BaseController
  include CsvExportConcern

  # The filter-bar convention: "all" means the filter is inactive.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  CSV_HEADER = ["Callsign", "Blocker", "Email", "Training Session",
                "Shift", "Timezone", "Description", "Position"].freeze

  def index
    @report = Training::UntrainedPeopleReport.execute(@training, @year)
    @filter_params = filter_params
    @people = filtered(@report.people)
    @blocker_counts = @report.people.group_by(&:blocker).transform_values(&:size)

    respond_to do |format|
      format.html
      # The export is the whole report, not the current view -- the filters
      # narrow the page to chase through, the CSV is the record of the year.
      format.csv { send_csv(csv_rows, filename: "#{@year}-#{training_slug}-untrained-people.csv") }
    end
  end

  private

  def filter_params
    { blocker: params[:blocker].presence || ALL_FILTER,
      callsign: params[:callsign].to_s.strip }
  end

  # The filters narrow the computed list in memory: it is already a small
  # array of people, and re-querying would re-derive the whole report.
  def filtered(people)
    blocker = @filter_params[:blocker]
    callsign = @filter_params[:callsign].downcase

    people.select do |row|
      (blocker == ALL_FILTER || row.blocker == blocker) &&
        (callsign.blank? || row.callsign.downcase.include?(callsign))
    end
  end

  # One row per shift sign-up. slot.begins is already the session's LOCAL
  # wall-clock time, so it is stamped with its zone rather than converted --
  # same as the trained-no-work export.
  def csv_rows
    rows = [CSV_HEADER]

    @report.people.each do |person_row|
      session = person_row.training_slot
      session_stamp = session ? "#{session.begins.strftime(DateTimeHelper::CSV_TIME)} #{session.description}" : ""

      person_row.shifts.each do |shift|
        rows << [person_row.callsign,
                 Training::UntrainedPeopleReport::BLOCKER_LABELS.fetch(person_row.blocker),
                 person_row.email,
                 session_stamp,
                 shift.begins.strftime(DateTimeHelper::CSV_TIME),
                 shift.timezone_abbr,
                 shift.description,
                 shift.position.title]
      end
    end
    rows
  end
end
