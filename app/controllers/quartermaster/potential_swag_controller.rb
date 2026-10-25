# frozen_string_literal: true

# Who might earn a service pin or patch at the coming event. (Ember
# reports/potential-swag port.)
#
# Deliberately NOT year-scoped: the roster is every active-status account and
# the milestone is all-time. Only the sign-up column asks about a year, and it
# always asks about Current.year -- the column header says so.
#
# Unlike Events Rangered next door, this page arrives unfiltered. Upstream has
# no filter at all, so any default scope would be an invention; it also means
# every filter's default here is already the "all" sentinel, and the chips and
# clear-all need no always: treatment.
class Quartermaster::PotentialSwagController < ApplicationController
  include CsvExportConcern
  include SignedUpFilterConcern

  layout "quartermaster"

  # Upstream's SwagPolicy#potentialSwagReport grants Quartermaster, with
  # before() granting Admin and Edit Swag. Note this is NOT the Events Rangered
  # gate: Timesheet Management belonged to TimesheetPolicy, which this report
  # never lived on.
  authorize_role [Role::ADMIN, Role::QUARTERMASTER, Role::EDIT_SWAG],
                 message: "Admin, Quartermaster, or Edit Swag role required " \
                          "to view potential swag."

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # Upstream's columns. "Last Worked" is renamed: "work" is banned UI
  # vocabulary, and a CSV header is user-facing text like any other.
  #
  # "Service Eligible" keeps upstream's wording where the page says "Service
  # swag", so a quartermaster with last year's spreadsheet open still finds the
  # column where it was.
  def self.csv_header(year)
    ["Callsign", "Status", "Total Years", "First Year", "Last Rangered",
     "#{year} Sign-Ups?", "Service Eligible"]
  end

  def index
    @rows = PotentialSwagReport.execute(Current.year)

    # Every status the roster holds. This is the validation set for the status
    # filter and the ordering for its select, so it stays unfiltered: a status
    # narrowed away still has to be choosable, or picking one would be a
    # one-way door.
    @status_counts = @rows.group_by(&:status).transform_values(&:size)

    # Named status_scope, not status: ActionController::Metal#status is a real
    # inherited method returning the HTTP status, so a local called status --
    # and the { status:, ... } shorthand below it -- is one edit away from
    # silently putting 200 into the filter params.
    #
    # Status is the page's primary scope. The stats and the milestone summary
    # both describe it, so narrowing to Active restates the whole order sheet
    # for people who are actually coming back.
    status_scope = status_filter(@status_counts)
    @scoped = (status_scope == ALL) ? @rows : @rows.select { |row| row.status == status_scope }

    # The summary keeps every milestone the status scope holds -- clicking a
    # line must not collapse the sheet it came from, and #milestone_filter
    # validates against these lines. What DOES follow the signed-up filter is
    # line[:matching], the roster a line's link actually delivers, so the
    # milestone select can stop printing a count it cannot honour.
    signed_up = signed_up_filter
    @milestones = PotentialSwagReport.milestones(@scoped) do |row|
      signed_up_match?(row, signed_up)
    end

    @filter_params = { status: status_scope, milestone: milestone_filter(@milestones),
                       signed_up: }
    @filtered = filtered(@scoped, @filter_params)

    # Column sums of the summary, not two more passes over @scoped: @milestones
    # is grouped from exactly the rows these describe.
    @milestone_count = @milestones.sum { |line| line[:people] }
    @milestone_signed_up_count = @milestones.sum { |line| line[:signed_up] }

    # What each status choice would actually deliver, so the status select
    # promises what the milestone select beside it promises. Keyed by
    # @status_counts, so a status narrowed to no one still appears, reading (0).
    @status_matching = status_matching_counts(@filter_params)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{Current.year}-potential-swag.csv") }
    end
  end

  private

  # An unrecognised status widens to all rather than narrowing to something
  # no one asked for. That is safe here only because all is also the default:
  # the page draws no status chip either way, so it cannot end up filtered
  # without saying so. The valid set is data-derived, so this is reachable from
  # any shared link whose status has since emptied out.
  #
  # The collections these filters validate against are arguments, not ivars:
  # the order index assigns them is then enforced by Ruby rather than by a
  # comment, and calling one too early is an ArgumentError at the call site.
  def status_filter(status_counts)
    status = params[:status].presence || ALL
    (status == ALL || status_counts.key?(status)) ? status : ALL
  end

  # A milestone outside the lines on offer would render an empty roster with no
  # way to tell a typo from a real gap, so it is dropped instead.
  def milestone_filter(milestones)
    milestone = params[:milestone].presence
    offered = milestones.any? { |line| line[:milestone].to_s == milestone }
    (milestone && offered) ? milestone : ALL
  end

  # Status is already applied to the scope, so only the other two run here.
  # In memory: the array is loaded for the summary anyway, and re-querying would
  # only re-derive it.
  def filtered(rows, filters)
    milestone = filters[:milestone]

    rows.select do |row|
      signed_up_match?(row, filters[:signed_up]) &&
        (milestone == ALL || row.milestone == milestone.to_i)
    end
  end

  # Per status, how many people survive the OTHER two filters -- the roster the
  # status select's own choice would hand over. Counted from @rows rather than
  # @scoped because choosing a status replaces the current one rather than
  # narrowing within it.
  def status_matching_counts(filters)
    # #filtered applies the milestone and signed-up filters and not status,
    # which is exactly the question here.
    matched = filtered(@rows, filters).group_by(&:status).transform_values(&:size)

    @status_counts.keys.index_with { |status| matched.fetch(status, 0) }
  end

  # The export carries whatever the filters currently show, in the page's
  # callsign order -- "5-year, active, not signed up" is the nudge list for
  # people about to miss their pin, and that is the file worth having.
  def csv_rows
    @filtered.each_with_object([self.class.csv_header(Current.year)]) do |row, rows|
      rows << [row.callsign, row.status, row.years, row.first_year, row.last_year,
               row.signed_up ? "Y" : "N", row.service_label]
    end
  end
end
