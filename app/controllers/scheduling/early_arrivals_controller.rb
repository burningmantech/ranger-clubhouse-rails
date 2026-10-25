# frozen_string_literal: true

# Who arrives before gate opening weekend, so their arrival packets can be put
# together ahead of time.
class Scheduling::EarlyArrivalsController < ApplicationController
  include CsvExportConcern

  layout "scheduling"

  # Arrival passes are the access document team's to issue and chase, so the
  # page answers to the same two roles the passes themselves do.
  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required " \
                          "to view the early arrivals report."

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # The selector's own floor. Left at the default it would offer decades of
  # years with no event dates on file, every one of which lands the reader on
  # the "dates are not set" callout.
  self.year_floor = 2008

  before_action :setup_year

  def index
    @report = EarlyArrivalReport.build(year: @year)

    respond_to do |format|
      format.html do
        @filter_params = UiComponents::FilterBarHelper.active_filters(filter_params)
        @rows = filtered_rows(@report.rows)
      end

      # Everyone, whatever the page is currently narrowed to. A file named for
      # the year that quietly held most of it back is one no one can trust --
      # and a year the report cannot be built for says so rather than handing
      # over an empty sheet that reads as "no one arrives early".
      format.csv do
        if @report.no_event_dates?
          redirect_to scheduling_early_arrivals_path(year: @year),
                      alert: "The #{@year} event dates are not set, so there is " \
                             "nothing to export yet."
        else
          send_csv(csv_rows, filename: "#{@year}-early-arrivals.csv")
        end
      end
    end
  end

  private

  # Anything the page does not offer shows everyone, so a stale bookmark or a
  # typo cannot narrow the list while drawing a chip that claims otherwise. The
  # two date filters are checked against the days actually on the report, which
  # is also what keeps a date the list has no one on from being accepted.
  #
  # Three of them read a pass or the on-playa flag, neither of which an earlier
  # year holds, so on those years they are not on offer and any value given for
  # them falls back to showing everyone.
  def filter_params
    known = UiComponents::FilterBarHelper.method(:known_filter)
    live = @report.live?

    {
      sap: live ? known.call(params[:sap], Scheduling::EarlyArrivalsHelper::SAP_FILTERS) : ALL,
      arrival: live ? known.call(params[:arrival], @report.arrival_date_keys) : ALL,
      shift: known.call(params[:shift], Scheduling::EarlyArrivalsHelper::SHIFT_FILTERS),
      shift_date: known.call(params[:shift_date], @report.shift_date_keys),
      agreement: known.call(params[:agreement], Scheduling::EarlyArrivalsHelper::AGREEMENT_FILTERS),
      site: live ? known.call(params[:site], Scheduling::EarlyArrivalsHelper::SITE_FILTERS) : ALL
    }
  end

  # Narrowed in Ruby: the whole list is already in hand to total it, and a
  # second trip to the database could only disagree with the figures on screen.
  def filtered_rows(rows)
    rows = filter_sap(rows)
    rows = filter_shift(rows)
    rows = filter_agreement(rows)
    rows = filter_site(rows)
    rows = filter_date(rows, @filter_params[:arrival], &:arrival_date)
    filter_date(rows, @filter_params[:shift_date], &:shift_date)
  end

  def filter_sap(rows)
    case @filter_params[:sap]
    when Scheduling::EarlyArrivalsHelper::SAP_ANY then rows.select(&:any_time?)
    when Scheduling::EarlyArrivalsHelper::SAP_DATED then rows.select(&:dated?)
    when Scheduling::EarlyArrivalsHelper::SAP_NONE then rows.select(&:no_sap?)
    else rows
    end
  end

  def filter_shift(rows)
    case @filter_params[:shift]
    when Scheduling::EarlyArrivalsHelper::SHIFT_YES then rows.select(&:shift?)
    when Scheduling::EarlyArrivalsHelper::SHIFT_NO then rows.reject(&:shift?)
    else rows
    end
  end

  def filter_agreement(rows)
    case @filter_params[:agreement]
    when Scheduling::EarlyArrivalsHelper::AGREEMENT_SIGNED then rows.select(&:radio_agreement)
    when Scheduling::EarlyArrivalsHelper::AGREEMENT_UNSIGNED then rows.reject(&:radio_agreement)
    else rows
    end
  end

  def filter_site(rows)
    case @filter_params[:site]
    when Scheduling::EarlyArrivalsHelper::SITE_ON then rows.select(&:on_site)
    when Scheduling::EarlyArrivalsHelper::SITE_OFF then rows.reject(&:on_site)
    else rows
    end
  end

  # The two date filters ask the same question of different days, so they share
  # one method and are told apart by the day each row hands back.
  #
  # A filter that is off arrives as nothing, the inactive ones having already
  # been dropped, so that has to read as "show everyone" -- matching rows
  # against nothing would empty the whole table.
  def filter_date(rows, value)
    return rows if value.blank?

    rows.select { |row| yield(row).to_s == value }
  end

  # One row per person, in the order the page lists them. The shift description
  # rides along with its position and start: it is where the person reports,
  # which is exactly what a packet is being assembled around.
  def csv_rows
    header = ["Callsign", "SAP", "First Pre-Event Position", "Shift Start",
              "Shift Description", "BMID Status", "On Site", "Radio Agreement",
              "Radio Count", "Radio Barcode", "Radio Type"]

    @report.rows.each_with_object([header]) do |row, rows|
      shift = row.first_shift

      rows << [row.callsign,
               helpers.early_arrival_sap_export(row.sap_date),
               shift&.position_title,
               # iso8601, and read in the page's own zone: an export is the
               # page in another format, so a shift near midnight has to name
               # the same day in both.
               shift&.begins&.iso8601,
               shift&.description,
               helpers.early_arrival_bmid_label(row.bmid_status),
               # An earlier year kept no record of who was on playa, so the
               # column says nothing rather than repeating today's answer.
               row.on_site.nil? ? "" : csv_yes_no(row.on_site),
               csv_yes_no(row.radio_agreement),
               row.radios_allowed,
               row.radios.map(&:barcode).join("\n"),
               row.radios.map(&:label).join("\n")]
    end
  end
end
