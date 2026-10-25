# frozen_string_literal: true

# Read-only audit of who may drive an org vehicle or bring a personal one.
# Port of Ember reports/vehicle-paperwork.
class Vehicles::PaperworkController < ApplicationController
  include CsvExportConcern

  layout "vehicles"

  # Upstream's CSV, in its own column order (its on-screen table puts the
  # checkbox columns somewhere else; one order now serves both).
  # Upstream's CSV plus the Personal Vehicle Agreement, which upstream never
  # exported but which the page now filters on.
  CSV_HEADERS = ["Callsign", "Status", "Vehicle Use Protocol", "Motor Vehicle Record Approved",
                 "Motor Vehicle Record Eligible", "Motor Vehicle Record Checkbox",
                 "Motor Vehicle Record Teams", "Motor Vehicle Record Granted Positions",
                 "Motor Vehicle Record Eligible Sign-Ups", "Personal Vehicle Agreement",
                 "Personal Vehicle Eligible", "Personal Vehicle Teams",
                 "Personal Vehicle Signed-Up Positions", "Personal Vehicle Checkbox"].freeze

  # Same floor as the sibling registry: there is no vehicle data before 2019.
  self.year_floor = 2019

  # Upstream: EVENT_MANAGEMENT or VEHICLE_INFO_UPDATE (VehiclePolicy::paperwork),
  # named here exactly.
  authorize_ability :view_paperwork,
                    roles: [Role::EVENT_MANAGEMENT, Role::VEHICLE_INFO_UPDATE],
                    deny_to: :me_root_path,
                    message: "Event Management or Vehicle Info Update role required to view vehicle paperwork."

  before_action :setup_year

  def index
    @filters = filter_params
    @callsign = @filters[:callsign].to_s
    @result = VehiclePaperworkReport.for_year(@year, @filters)

    respond_to do |format|
      format.html
      # The rows are the ones on screen, so the filters narrow the sheet the
      # same way they narrow the page.
      format.csv { send_csv(csv_rows, filename: "#{@year}-vehicle-paperwork.csv") }
    end
  end

  helper_method :index_params

  private

  # Only the filters that are actually narrowing the list travel in a URL. The
  # "all" sentinel is present?, so it survives compact_blank and would ride
  # along in every link; active_filters is the one place that drops it.
  # :callsign is free text -- a callsign could legitimately read "all" -- so it
  # is re-added on plain presence.
  def filter_params
    permitted = params.permit(*VehiclePaperworkReport::FILTER_KEYS).to_h.symbolize_keys

    narrowing = UiComponents::FilterBarHelper.active_filters(permitted.except(:callsign))
    narrowing[:callsign] = permitted[:callsign].strip if permitted[:callsign].present?
    narrowing
  end

  # Links back to this page keep the reader where they were.
  def index_params
    @filters.merge(year: @year)
  end

  def csv_rows
    [CSV_HEADERS] + @result.rows.map { |row| csv_row(row) }
  end

  def csv_row(row)
    [row.callsign,
     row.status,
     csv_yes_no(row.signed_vup),
     csv_yes_no(row.record_approved),
     csv_yes_no(row.mvr_eligible?),
     csv_yes_no(row.mvr_checkbox),
     csv_membership(row.mvr_teams),
     csv_membership(row.mvr_positions),
     row.mvr_signups.map { |signup| csv_signup(signup) }.join("\n"),
     csv_yes_no(row.pvr_approved),
     csv_yes_no(row.pvr_eligible?),
     csv_membership(row.pvr_teams),
     row.pvr_positions.join("\n"),
     csv_yes_no(row.pvr_checkbox)]
  end

  # A blank team or granted-position cell means "confirmed none" in a
  # current-year sheet. For any other year neither was looked up -- person_team
  # and person_position keep no history -- and the export is the copy people act
  # on, so it has to say which of the two it is. Same rule the registry's CSV
  # follows for its own current-year-only enrichment.
  def csv_membership(titles)
    return "not checked" unless @result.memberships_checked?

    titles.join("\n")
  end

  # slot.begins is stored as local wall-clock, so the offset a Time#to_s tacks
  # on is noise at best and a lie at worst. Print the digits as they are.
  def csv_signup(signup)
    begins = signup.begins
    stamp = begins.respond_to?(:strftime) ? begins.strftime(DateTimeHelper::CSV_TIME) : begins.to_s

    "#{signup.position_title} #{stamp}"
  end
end
