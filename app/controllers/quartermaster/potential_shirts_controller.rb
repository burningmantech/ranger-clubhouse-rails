# frozen_string_literal: true

# Who may earn a t-shirt or long sleeve for an event year, with per-title
# order lines. (Ember reports/potential-shirts port.)
#
# The first year-scoped quartermaster page: the year selector picks which
# event's hours are counted, matching upstream's selector (2010 floor, skip
# the pandemic years). Earning is decided against the two shirt hour
# thresholds in Settings.
class Quartermaster::PotentialShirtsController < ApplicationController
  include CsvExportConcern
  include ShirtFilterConcern

  layout "quartermaster"

  before_action :setup_year

  # Upstream's YearSelect minYear.
  self.year_floor = 2010

  # Upstream gates on Quartermaster, with TimesheetPolicy#before granting
  # Admin and Timesheet Management app-wide. That last one is incidental --
  # the report lives on Timesheet's policy -- but dropping it would be an
  # access regression, so it is carried over, as Events Rangered does.
  authorize_role [Role::ADMIN, Role::QUARTERMASTER, Role::TIMESHEET_MANAGEMENT],
                 message: "Admin, Quartermaster, or Timesheet Management role required " \
                          "to view potential shirts."

  # The earned filter's values: past the t-shirt line, past the long-sleeve
  # line, or short of both.
  EARNED_T_SHIRT = "t-shirt"
  EARNED_LONG_SLEEVE = "long-sleeve"
  EARNED_NONE = "none"
  EARNED_VALUES = [EARNED_T_SHIRT, EARNED_LONG_SLEEVE, EARNED_NONE].freeze

  COUNTS_HEADER = ["Shirt Kind", "Shirt", "Earned", "Pending"].freeze

  # Upstream's CSV columns, with the year and thresholds carried in the
  # headers the same way -- the file has no chips to say what it covers.
  def self.roster_header(year, threshold_ss, threshold_ls)
    ["Callsign", "First Name", "Last Name",
     "Estimated Hours in #{year}", "Hours in #{year}",
     "T-Shirt (#{threshold_ss} hrs)", "T-Shirt Backup",
     "Long Sleeve (#{threshold_ls} hrs)"]
  end

  def index
    load_report

    respond_to do |format|
      format.html
      format.csv { send_csv(roster_rows, filename: "#{@year}-potential-shirts.csv") }
    end
  end

  # Upstream downloaded one file per shirt kind, an artifact of its tabbed
  # layout. One file naming its kind per row opens as one sheet instead.
  def counts
    load_report

    send_csv(counts_rows, filename: "#{@year}-potential-shirt-counts.csv")
  end

  private

  def load_report
    # throw_on_empty, as upstream: both thresholds default to 0, and a page
    # quietly rendered against 0 marks the entire roster as earned -- an
    # order sheet that looks correct and is not. Failing loudly on an unset
    # threshold is the safer wrong.
    thresholds = Setting.get_value([Setting::SHIRT_SHORT_SLEEVE_HOURS_THRESHOLD,
                                    Setting::SHIRT_LONG_SLEEVE_HOURS_THRESHOLD],
                                   throw_on_empty: true)
    @threshold_ss = thresholds[Setting::SHIRT_SHORT_SLEEVE_HOURS_THRESHOLD]
    @threshold_ls = thresholds[Setting::SHIRT_LONG_SLEEVE_HOURS_THRESHOLD]

    @rows = PotentialShirtsReport.execute(@year, threshold_ss: @threshold_ss,
                                                 threshold_ls: @threshold_ls)
    @kinds = PotentialShirtsReport.order_lines(@rows)
    @earned_ss_count = @rows.count(&:earned_ss)
    @earned_ls_count = @rows.count(&:earned_ls)
    @below_count = @rows.size - @earned_ss_count

    @filter_params = filter_params
    @filtered_rows = filtered(@rows)
  end

  # Earned first, then one per shirt kind, then the catch-all -- the order the
  # chips read in. The kind and missing params are normalised by
  # ShirtFilterConcern.
  def filter_params
    { earned: EARNED_VALUES.include?(params[:earned]) ? params[:earned] : ALL,
      **shirt_filter_params }
  end

  # Filters narrow the roster in memory: it is a small array already loaded
  # for the order lines, and re-querying would only re-derive it. The order
  # lines and the stats stay whole -- they are the order sheet, and narrowing
  # to one style must not make it look like no one else needs a shirt.
  def filtered(rows)
    rows.select do |row|
      earned_match?(row) && shirt_filters_match?(row.person, @filter_params)
    end
  end

  def earned_match?(row)
    case @filter_params[:earned]
    when EARNED_T_SHIRT then row.earned_ss
    when EARNED_LONG_SLEEVE then row.earned_ls
    when EARNED_NONE then !row.earned_ss && !row.earned_ls
    else true
    end
  end

  # The export carries whatever the filters currently show -- narrowing to
  # "long sleeve pending" is a nudge list, and the point is to act on it.
  # Titles print as "not earned" for shirts short of their threshold, as
  # upstream's export did.
  def roster_rows
    rows = [self.class.roster_header(@year, @threshold_ss, @threshold_ls)]

    @filtered_rows.each do |row|
      person = row.person
      rows << [person.callsign, person.desired_first_name, person.last_name,
               row.estimated_hours, row.actual_hours,
               *@kinds.map { |kind| csv_shirt(row, kind) }]
    end

    rows
  end

  def csv_shirt(row, kind)
    earned = row.public_send(PotentialShirtsReport::EARNED_FLAG.fetch(kind.param))
    earned ? ShirtTotals.title_for(row.person, kind.reader) : "not earned"
  end

  # The whole report, never the filtered view: this file is the order sheet.
  def counts_rows
    rows = [COUNTS_HEADER]

    @kinds.each do |kind|
      kind.lines.each { |line| rows << [kind.name, line.title, line.earned, line.pending] }
    end

    rows
  end
end
