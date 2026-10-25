# frozen_string_literal: true

# Years of service for everyone who has rangered, with the service-length
# distribution above the roster. (Ember reports/events-rangered port.)
#
# Deliberately NOT year-scoped: the census is all-time and there is no year
# selector. Only the Signed Up column asks about a year, and it always asks
# about Current.year -- the column header says so.
class Quartermaster::EventsRangeredController < ApplicationController
  include CsvExportConcern
  include SignedUpFilterConcern

  layout "quartermaster"

  # Upstream gates this on Quartermaster, with TimesheetPolicy#before granting
  # Admin and Timesheet Management. That last one is incidental -- the report
  # lived on TimesheetController -- but dropping it would be an access
  # regression, so it is carried over.
  authorize_role [Role::ADMIN, Role::QUARTERMASTER, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin, Quartermaster, or Timesheet Management role required " \
                          "to view years of service."

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # Upstream's columns, plus Status -- upstream had no status filter, this page
  # does, so which scope produced the file has to travel with it. The last
  # column carries the year for the same reason it does upstream: the census
  # itself is all-time, so "Signed Up" alone would not say which event.
  def self.csv_header(year)
    ["Callsign", "Last Name", "First Name", "Status", "Years",
     "First Year", "Last Year", "Signed Up In #{year}"]
  end

  def index
    @rows = EventsRangeredReport.execute(Current.year)
    @status_counts = @rows.group_by(&:status).transform_values(&:size)

    # Status is the page's primary scope -- upstream's Active/All radio, widened
    # to the statuses the census actually holds. The stats describe this scope.
    status = status_filter
    @scoped = (status == ALL) ? @rows : @rows.select { |row| row.status == status }
    @signed_up_count = @scoped.count(&:signed_up)
    # @scoped is already sorted longest service first.
    @longest_service = @scoped.first&.years || 0

    # The distribution keeps every band the status scope holds -- clicking a bar
    # must not collapse the chart it came from, and #years_filter validates
    # against these bands, so narrowing them would start dropping years the
    # reader legitimately picked. What DOES follow the signed-up filter is
    # bucket[:matching], the roster a band's link actually delivers, so the
    # years select can stop printing a count it cannot honour.
    signed_up = signed_up_filter
    @distribution = EventsRangeredReport.distribution(@scoped) do |row|
      signed_up_match?(row, signed_up)
    end

    # After @distribution: #years_filter is checked against the buckets this
    # page actually offers.
    @filter_params = { status:, years: years_filter, signed_up: }
    @filtered = filtered(@scoped)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{Current.year}-events-rangered.csv") }
    end
  end

  private

  # Defaults to Active, matching upstream's radio. The default draws a visible
  # chip on purpose: the page is filtered on arrival and should say so.
  #
  # An unrecognised status falls back to that same default, NOT to ALL. Falling
  # back to ALL would answer a narrowing request with the entire census while
  # drawing no chip to admit it -- and the export, which has no chips at all,
  # would write every status to a file named for none of them. The valid set is
  # data-derived, so this is reachable from any shared link whose status has
  # since emptied out.
  def status_filter
    status = params[:status].presence || Person::ACTIVE
    return status if status == ALL || @status_counts.key?(status)

    # Falling back to Active when the census holds no Active people would apply
    # a filter the select cannot show -- Rails marks nothing selected for a
    # value absent from the choices, so the page would draw an "Active" chip
    # over an empty roster while the select read "All", and re-submitting the
    # form as displayed would silently widen the scope. All is always offered.
    @status_counts.key?(Person::ACTIVE) ? Person::ACTIVE : ALL
  end

  # A years value outside the buckets on offer would render an empty roster with
  # no way to tell a typo from a real gap, so it is dropped instead.
  def years_filter
    years = params[:years].presence
    (years && @distribution.any? { |bucket| bucket[:years].to_s == years }) ? years : ALL
  end

  # Status is already applied to the scope, so only the other two run here.
  # In memory: the array is loaded for the distribution anyway, and re-querying
  # would only re-derive it.
  def filtered(rows)
    years = @filter_params[:years]

    rows.select do |row|
      signed_up_match?(row, @filter_params[:signed_up]) &&
        (years == ALL || row.years == years.to_i)
    end
  end

  # The export carries whatever the filters currently show. Unlike the Alpha
  # Shirts order sheet, this one is a call list -- the point of narrowing to
  # "ten years, not signed up" is to act on those people.
  #
  # The last-name sort is upstream's; see .csv_header for the columns.
  def csv_rows
    sorted = @filtered.sort_by { |row| [row.last_name.downcase, row.first_name.downcase] }

    sorted.each_with_object([self.class.csv_header(Current.year)]) do |row, rows|
      rows << [row.callsign, row.last_name, row.first_name, row.status, row.years,
               row.first_year, row.last_year, row.signed_up ? "Y" : "N"]
    end
  end
end
