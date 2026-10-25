# frozen_string_literal: true

# Shift starts that were forced past a sign-in blocker (Ember
# reports/forced-signins port). An audit page: every forced start of the year,
# the checks that were overridden, and the reason the forcer typed.
class Timesheets::ForcedShiftStartController < ApplicationController
  include CsvExportConcern

  layout "timesheets"

  # Upstream TimesheetPolicy: the before hook admits Admin and Timesheet
  # Management, and forcedSigninsReport() admits Event Management. Deliberately
  # NOT the roles that may force a start -- Can Force Shift Start is the
  # permission this page reviews, not a claim on reading the review.
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT, Role::EVENT_MANAGEMENT],
                 message: "Admin, Timesheet Management, or Event Management role required " \
                          "to view forced shift starts."

  # Upstream's own floor. Left at the 1998 default, a year the URL is allowed to
  # ask for is a year the selector cannot show, and picking it back fires no
  # change event.
  self.year_floor = 2018

  before_action :setup_year

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  def index
    @all_entries = ForcedShiftStartReport.execute(year: @year)
    @filters = filter_params
    @entries = apply_filters(@all_entries)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{@year}-forced-shift-starts.csv") }
    end
  end

  private

  # Values are normalized to the "all" sentinel unless they name something the
  # year's forced starts actually hold. Anything else -- a stale bookmark, a
  # typo, `?person_id[]=1` -- would otherwise narrow nothing while still drawing
  # a chip claiming it did, and an Array would crash the chip's URL builder.
  def filter_params
    known = UiComponents::FilterBarHelper.method(:known_filter)

    { person_id: known.call(params[:person_id], values(:person_id)),
      forced_by_id: known.call(params[:forced_by_id], values(:forced_by_id)),
      position_id: known.call(params[:position_id], values(:position_id)),
      blocker: known.call(params[:blocker], @all_entries.flat_map(&:blocker_names)) }
  end

  def values(attribute)
    @all_entries.filter_map { |entry| entry.public_send(attribute)&.to_s }
  end

  # Filters combine: the four narrow together, and the export carries whatever
  # the page is showing so the file and the screen say the same thing.
  def apply_filters(entries)
    filters = @filters

    entries.select { |entry|
      matches?(filters[:person_id], entry.person_id) &&
        matches?(filters[:forced_by_id], entry.forced_by_id) &&
        matches?(filters[:position_id], entry.position_id) &&
        (filters[:blocker] == ALL || entry.blocker_names.include?(filters[:blocker]))
    }
  end

  def matches?(filter, value) = filter == ALL || value.to_s == filter

  # Upstream's columns. Blockers are one per line inside the cell, as the page
  # renders them, so screen and file say the same thing.
  def csv_rows
    rows = [["Person", "Position", "Shift Start", "Forced By", "Blockers", "Reason"]]

    @entries.each do |entry|
      # person_display_name, not a bare callsign: a forcer whose person row is
      # gone reads "Deleted #N" on the page, and an empty cell here would leave
      # the auditor unable to tell that from a start with no log at all.
      rows << [entry.callsign, entry.position_title, entry.on_duty.iso8601,
               helpers.person_display_name(entry.forced_by, entry.forced_by_id, blank: nil),
               blocker_text(entry), entry.reason]
    end

    rows
  end

  def blocker_text(entry)
    entry.blockers.map { |blocker| helpers.timesheet_blocker_label(blocker) }.join("\n")
  end
end
