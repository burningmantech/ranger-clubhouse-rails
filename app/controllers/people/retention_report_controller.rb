# frozen_string_literal: true

# Everyone who rangered any of the last five events, for the retention survey.
#
# Not year-scoped and there is no year selector: the window always ends at the
# current year, because the survey always follows the event that just ended.
class People::RetentionReportController < ApplicationController
  include CsvExportConcern

  layout "people"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or VC role required to view the retention report."

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # Upstream's columns, in upstream's order.
  CSV_HEADER = ["Callsign", "Name", "Status", "Email",
                "First Year", "Last Year", "Total Years"].freeze

  def index
    @report = RetentionReport.execute
    @status_counts = @report.status_counts
    @counts_by_last_year = @report.counts_by_last_year

    @filter_params = { status: status_filter, last_year: last_year_filter }
    @rows = filtered(@report.rows, @filter_params)

    # A select navigates with the page's other filter still applied, so its
    # counts have to promise the roster the choice delivers rather than the
    # roster before filtering. Ordering still comes from the full counts, so
    # the options do not reshuffle as the other filter changes.
    @matching_status_counts = matching_counts(:status, :status)
    @matching_year_counts = matching_counts(:last_year, :last_year_key)

    respond_to do |format|
      format.html
      format.csv do
        send_csv(csv_rows, filename: "retention-report-#{@report.end_year}.csv")
      end
    end
  end

  private

  # The page opens counting everybody. A status it does not offer counts
  # everybody too, rather than narrowing to nothing with no way to tell a stale
  # link from a real gap.
  def status_filter
    UiComponents::FilterBarHelper.known_filter(params[:status], @status_counts.keys)
  end

  # Same for the year: only the years the report actually holds are honoured.
  def last_year_filter
    offered = @report.rows.map(&:last_year_key).uniq
    UiComponents::FilterBarHelper.known_filter(params[:last_year], offered)
  end

  # In memory: the rows are loaded for the counts anyway, and re-querying would
  # only re-derive them. Filters arrive as an argument so a caller can ask for a
  # partial set -- each select's counts need the roster narrowed by the OTHER
  # filter only.
  def filtered(rows, filters)
    status = filters[:status] || ALL
    last_year = filters[:last_year] || ALL
    return rows if status == ALL && last_year == ALL

    rows.select do |row|
      (status == ALL || row.status == status) &&
        (last_year == ALL || row.last_year_key == last_year)
    end
  end

  # What one select can promise: the rows the page's other filter leaves.
  def matching_counts(key, attribute)
    filtered(@report.rows, @filter_params.except(key))
      .group_by(&attribute)
      .transform_values(&:size)
  end

  # The survey goes out by email, so the file carries names and addresses. Both
  # roles that may open this page may already see both, which is why the role
  # gate above is the whole of the check.
  #
  # The export carries whatever the filters currently show: the point of
  # narrowing to "inactive, last rangered 2024" is to send those people a
  # survey.
  def csv_rows
    @rows.each_with_object([CSV_HEADER]) do |row, rows|
      rows << [row.callsign, row.name, row.status, row.email,
               row.first_year, row.last_year, row.total_years]
    end
  end
end
