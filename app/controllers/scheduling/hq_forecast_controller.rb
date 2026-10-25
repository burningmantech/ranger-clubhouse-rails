# frozen_string_literal: true

# How busy the HQ window is expected to be, period by period, and whether it is
# staffed for it. Two pages of the same year: every shift, and each burn.
class Scheduling::HqForecastController < ApplicationController
  include CsvExportConcern

  layout "scheduling"

  # The same readers as the other schedule reports: the people who build the
  # board and the people who run the event off it.
  authorize_role [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT],
                 message: "Admin, Edit Slots, or Event Management role required " \
                          "to view the HQ forecast."

  # The earliest year the report has ever been offered for.
  self.year_floor = 2008

  before_action :setup_year
  before_action :set_interval

  # Both formats want the whole year, so it is read once above the split. Only
  # the page narrows; the export always carries every period.
  def index
    @report = HqForecastReport.execute(year: @year, interval: @interval)

    respond_to do |format|
      format.html { set_filters }
      format.csv do
        send_csv(HqForecastReport.csv_rows(@report), filename: "#{@year}-hq-forecast.csv")
      end
    end
  end

  def burn_perimeters
    @burns = HqForecastReport.burn_perimeters(year: @year, interval: @interval)
  end

  # The people behind one staffing count, for the dialog it opens.
  def people
    # Parsed rather than converted, for the reason spelled on the period width:
    # a nested value has no number to ask for and would raise instead of being
    # turned away.
    @desk = HqForecastReport.desk_for(HqForecastReport.parse_id(params[:position_id]))
    return head :not_found unless @desk

    # Parsing can fail outright as well as come back empty -- a date naming a
    # month that does not exist raises rather than returning nothing.
    @period = begin
      Time.zone.parse(params[:period].to_s)
    rescue ArgumentError
      nil
    end
    return head :not_found unless @period

    @people = HqForecastReport.people_in_period(position_id: @desk.position_id,
                                                period: @period, interval: @interval)
  end

  # The people behind one shift's bar on the chart, in the same dialog.
  def shift
    @shift, @people = HqForecastReport.people_on_shift(HqForecastReport.parse_id(params[:slot_id]))
    head :not_found unless @shift
  end

  private

  def set_interval
    @interval = HqForecastReport.normalize_interval(params[:interval])
  end

  # The day can only be checked against the report itself, since which days
  # exist depends on the year and how wide the periods are.
  def set_filters
    @day = UiComponents::FilterBarHelper.known_filter(params[:day], @report.day_keys)
    @days = @report.filtered_days(@day)
    @index_params = UiComponents::FilterBarHelper.active_filters(year: @year, interval: @interval, day: @day)
  end
end
