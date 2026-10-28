# frozen_string_literal: true

# The online-course progress report page (Ember training/:position_id/
# online-course-progress). Read-only; resolution, the tree view gate, and
# @year come from the base controller, and this page tightens to the
# OnlineCoursePolicy#progressReport roles on top -- Dirt Mentors and VCs see
# the tree but not this report.
class Training::OnlineCourseProgressController < Training::BaseController
  include CsvExportConcern

  # The filter-bar convention: "all" means the filter is inactive.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  # Upstream CSV parity: the Ember exporter's five columns.
  CSV_HEADER = ["Callsign", "Status", "Moodle Username",
                "Enrolled At (Pacific)", "Completed At (Pacific)"].freeze

  before_action :authorize_progress_report

  def index
    @report = Training::OnlineCourseProgressReport.execute(@training, @year)

    respond_to do |format|
      format.html do
        @filter_params = filter_params
        @rows = filtered(@report.enrollments)
      end
      # The export is the whole report, not the current view -- the filters
      # narrow the page to work through, the CSV is the record of the year.
      format.csv { send_csv(csv_rows, filename: "#{@year}-#{training_slug}-online-course-progress.csv") }
    end
  end

  private

  def filter_params
    { status: params[:status].presence || ALL_FILTER,
      progress: params[:progress].presence || ALL_FILTER,
      callsign: params[:callsign].to_s.strip }
  end

  # The filters narrow the loaded list in memory, same as the sibling
  # reports: the page renders the whole year anyway, so there is nothing to
  # re-query.
  def filtered(enrollments)
    status = @filter_params[:status]
    progress = @filter_params[:progress]
    callsign = @filter_params[:callsign].downcase
    return enrollments if status == ALL_FILTER && progress == ALL_FILTER && callsign.blank?

    enrollments.select do |poc|
      (status == ALL_FILTER || poc.person.status == status) &&
        @report.matches_progress?(poc, progress) &&
        (callsign.blank? || poc.person.callsign.downcase.include?(callsign))
    end
  end

  # A NULL enrolled_at is a direct Moodle enrollment with no known date --
  # it exports as an empty cell, same as upstream. The times are on Pacific's
  # clock, as the headers say.
  def csv_rows
    rows = [CSV_HEADER]

    @report.enrollments.each do |poc|
      rows << [poc.person.callsign,
               poc.person.status,
               poc.person.lms_username,
               pacific_csv_time(poc.enrolled_at),
               pacific_csv_time(poc.completed_at)]
    end
    rows
  end

  def pacific_csv_time(time) = time&.in_time_zone(DateTimeHelper::PACIFIC)&.strftime(DateTimeHelper::CSV_TIME)

  def authorize_progress_report
    return if has_role?(Training.online_course_progress_roles(@training))

    not_authorized_redirect("You are not authorized to view the online course progress report.")
  end
end
