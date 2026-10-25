# frozen_string_literal: true

# The trained-but-never-rangered report page (Ember training/:position_id/
# trained-no-work). Read-only; resolution, the TrainingPolicy view gate, and
# @year come from the base controller.
class Training::TrainedNoWorkController < Training::BaseController
  include CsvExportConcern

  # The filter-bar convention: "all" means the filter is inactive.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  CSV_HEADER = ["Callsign", "Status", "Qualified Via", "Session", "Timezone", "Description"].freeze

  def index
    @report = Training::TrainedNoWorkReport.execute(@training, @year)
    @filter_params = filter_params
    @people = filtered(@report.people)
    @status_counts = @report.people.group_by(&:status).transform_values(&:size)
    # Counts overlap on purpose -- someone who both passed and taught is in
    # both, because each count answers "how many rows would this choice show?"
    @via_counts = @report.people.flat_map { |trainee| trainee.qualifications.map(&:kind).uniq }.tally

    respond_to do |format|
      format.html
      # The export is the whole report, not the current view -- the filters
      # narrow the page to work through, the CSV is the record of the year.
      format.csv { send_csv(csv_rows, filename: "#{@year}-#{training_slug}-trained-no-work.csv") }
    end
  end

  private

  def filter_params
    { status: params[:status].presence || ALL_FILTER,
      via: params[:via].presence || ALL_FILTER,
      callsign: params[:callsign].to_s.strip }
  end

  # The filters narrow the computed list in memory: it is already a small array
  # of people, and re-querying would have to re-derive the whole report. Someone
  # who both passed and taught matches either side of the via filter.
  def filtered(people)
    status = @filter_params[:status]
    via = @filter_params[:via]
    callsign = @filter_params[:callsign].downcase

    people.select do |trainee|
      (status == ALL_FILTER || trainee.status == status) &&
        (via == ALL_FILTER || trainee.qualifications.any? { |q| q.kind.to_s == via }) &&
        (callsign.blank? || trainee.callsign.downcase.include?(callsign))
    end
  end

  # One row per qualification, so a person who both passed and taught shows
  # both. slot.begins is already the session's LOCAL wall-clock time, so it is
  # stamped with its zone rather than converted (Slot#begins_adjusted would
  # shift any session outside the app zone) -- hence the Timezone column, same
  # as the trainer attendance export.
  def csv_rows
    rows = [CSV_HEADER]

    @report.people.each do |trainee|
      trainee.qualifications.each do |qualification|
        rows << [trainee.callsign,
                 trainee.status,
                 qualification.kind.to_s.capitalize,
                 qualification.slot.begins.strftime(DateTimeHelper::CSV_TIME),
                 qualification.slot.timezone_abbr,
                 qualification.slot.description]
      end
    end
    rows
  end
end
