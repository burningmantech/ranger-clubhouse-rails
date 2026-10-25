# frozen_string_literal: true

# Who is scheduled at each post, period by period, for one kind of shift. One
# page: the year, the shift type, and the day all ride in the query string.
class Scheduling::ShiftCoverageController < ApplicationController
  include CsvExportConcern

  layout "scheduling"

  # The same readers as the other schedule reports: the people who build the
  # board and the people who run the event off it.
  authorize_role [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT],
                 message: "Admin, Edit Slots, or Event Management role required " \
                          "to view shift coverage."

  # The earliest year the report has ever been offered for.
  self.year_floor = 2008

  before_action :setup_year
  before_action :set_type

  # Both formats want the whole year, so it is read once above the split. Only
  # the page narrows to a day; the export always carries every one of them.
  def index
    @report = ShiftCoverageReport.execute(year: @year, coverage: @coverage)

    respond_to do |format|
      format.html { set_day }
      format.csv do
        send_csv(ShiftCoverageReport.csv_rows(@report),
                 filename: "#{@year}-shift-coverage-#{@type}.csv")
      end
    end
  end

  private

  # The slug the report answers with, which is not always the one asked for:
  # a shift type that does not exist falls back, and with none set up there is
  # no slug at all. The Shift Type menu comes from the same read.
  def set_type
    groups = ShiftCoverageGroup.ordered.to_a
    @coverage = ShiftCoverageReport.type_for(params[:type], groups)
    @type = @coverage&.slug
    @type_options = groups.map { |group| [group.title, group.slug] }
  end

  # The day can only be checked against the report itself, since which days
  # exist depends on the year and the shift type that were asked for.
  def set_day
    @day = UiComponents::FilterBarHelper.known_filter(params[:day], @report.day_keys)
    @days = @report.filtered_days(@day)
    # The shift type is what the report is about, not something narrowing it, so
    # it stays out of active_filters, which drops the filter bar's "all": a shift
    # type slugged "all" would otherwise lose its place in every link built here.
    @index_params = { year: @year, type: @type }.compact
                                                .merge(UiComponents::FilterBarHelper.active_filters(day: @day))
  end
end
