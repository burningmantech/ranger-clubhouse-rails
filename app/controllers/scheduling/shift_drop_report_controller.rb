# frozen_string_literal: true

# Who dropped a shift close to its start, position by position. The positions
# index drills down into one position's shifts, as the flake report beside it
# does.
class Scheduling::ShiftDropReportController < ApplicationController
  include CsvExportConcern
  include PositionLookupConcern

  layout "scheduling"

  # Upstream TimesheetPolicy: the before hook admits Admin and Timesheet
  # Management, and shiftDropReport() admits Event Management. Deliberately NOT
  # the flake report's role set next door -- Edit Slots reads that page and has
  # no claim on this one. (The Ember route gates on MANAGE, which the API never
  # honored; the policy is the authority.)
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT, Role::EVENT_MANAGEMENT],
                 message: "Admin, Timesheet Management, or Event Management role required " \
                          "to view the shift drop report."

  # The year selector's own floor, matching upstream's list. Left at the 1998
  # default, a year the URL is allowed to ask for is a year the selector cannot
  # show, and picking it back fires no change event.
  self.year_floor = 2019

  before_action :setup_year
  before_action :set_hours
  before_action :set_position, only: :position

  # The summary is built inside the html branch, not above the respond_to: the
  # export needs none of it, and computing it there ran the year's whole slot
  # and removal scan a second time for a result the CSV branch never reads.
  def index
    respond_to do |format|
      format.html { @summary = ShiftDropReport.summary(year: @year, hours: @hours) }
      # The pages are one position at a time; the export is the whole year.
      # The window rides in the filename too -- exporting at one hour and then
      # at forty-eight otherwise hands the reader two different reports under
      # one name.
      format.csv { send_csv(csv_rows, filename: "#{@year}-shift-drops-within-#{@hours}h.csv") }
    end
  end

  def position
    @detail = ShiftDropReport.position(year: @year, hours: @hours, position: @position)
  end

  private

  # The window is half the question this report answers, so it travels in every
  # link the pages build -- drill-downs, the export, and the year selector. Left
  # off, following any of them silently answers a different question than the
  # one on screen.
  def set_hours
    @hours = ShiftDropReport.normalize_hours(params[:hours])
    @index_params = { year: @year, hours: @hours }
  end

  # Back to the list the reader was filtering, not a bare one.
  def position_not_found_path
    scheduling_shift_drop_report_path(@index_params)
  end

  # Upstream emits Callsign twice and no shift description, which leaves the
  # parallel shifts of one position indistinguishable in the file. Hours stay
  # decimal, as upstream's export has them.
  #
  # getlocal before iso8601, as the sibling report libs do: a datetime read
  # comes back cast into Time.zone, an hour ahead of the stored wall clock for
  # the half of the year the machine is not on the same offset. Without it a
  # January shift exports an hour later than the page and the schedule show it.
  def csv_rows
    drops = ShiftDropReport.all_drops(year: @year, hours: @hours)
    titles = Position.titles_by_id(drops.map { |drop| drop.slot.position_id }.uniq)
    rows = [["Position", "Shift Start", "Shift", "Callsign", "Dropped At", "Hours Before Start"]]

    sorted_for_export(drops, titles).each do |drop|
      rows << [titles[drop.slot.position_id], drop.slot.begins.getlocal.iso8601, drop.slot.description,
               drop.callsign, drop.dropped_at.getlocal.iso8601, drop.hours_before]
    end

    rows
  end

  # The reading order of the pages: position, then shift, then the order they
  # left in.
  def sorted_for_export(drops, titles)
    drops.sort_by do |drop|
      [titles[drop.slot.position_id].downcase, drop.slot.begins, drop.dropped_at]
    end
  end
end
