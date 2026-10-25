# frozen_string_literal: true

# Hours per year -- and, when asked, sign-ups -- for the positions a reader
# picks. One page: the positions, the span and both options ride in the query
# string, so a report can be bookmarked and passed on, and the export is the
# page's own address with a format on the end.
class TeamsPositions::SpecialTeamsHoursController < ApplicationController
  include CsvExportConcern

  layout "teams_positions"

  # Upstream's API let in Admin and Timesheet Management through TimesheetPolicy's
  # before hook and Event Management through the report's own rule, but the page
  # sat in the Ember reports area, which only Admin and Event Management could
  # open. Those are the people who ran it, so they are who this admits.
  # Read-only either way: nothing here writes.
  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT],
                 message: "Admin or Event Management role required to view special teams hours."

  # The most people the page shows. The export is not capped -- a spreadsheet is
  # how you handle thousands of rows -- but every position over every year is
  # some 5,700 rows, a 19 MB page a browser takes seconds to lay out.
  ROW_LIMIT = 500

  def index
    @form = SpecialTeamsHoursForm.new(form_params.to_h.merge(position_ids: chosen_ids))
    @report = run_report if submitted? && @form.valid?

    respond_to do |format|
      format.html do
        @groups = position_groups
        @rows = @report&.rows&.first(ROW_LIMIT)
      end
      format.csv { send_export }
    end
  end

  private

  def submitted? = form_params.present? || chosen_ids.present?

  def form_params
    @form_params ||= scoped_params(SpecialTeamsHoursForm::PARAM_SCOPE,
                                   :start_year, :end_year, :include_holders, :show_signups)
  end

  # The picker's ids[] parameters, or a single ids=N from a hand-written link.
  # Anything else -- a nested hash -- counts as no position chosen.
  def chosen_ids
    ids = params[SpecialTeamsHoursForm::IDS_PARAM]
    ids if ids.is_a?(String) || ids.is_a?(Array)
  end

  def run_report
    SpecialTeamsHoursReport.execute(position_ids: @form.position_ids,
                                    start_year: @form.start_year,
                                    end_year: @form.end_year,
                                    include_holders: @form.include_holders,
                                    show_signups: @form.show_signups)
  end

  # Every position, grouped by team for the picker. Inactive positions are
  # offered too -- the hours on them are still somebody's.
  def position_groups
    PositionGroups.by_team(Position.select(:id, :title, :active, :team_id).order(:title))
  end

  # A download only makes sense once the report has run. Anything else lands on
  # the page carrying whatever was asked for, so a stale bookmark arrives at the
  # reason rather than at a file with nothing in it.
  def send_export
    if @report.nil?
      carried = submitted? ? @form.query_params : {}
      return redirect_to(teams_positions_special_teams_hours_path(carried))
    end

    send_csv(csv_rows, filename: "special-teams-hours-#{@report.start_year}-#{@report.end_year}.csv")
  end

  # The table on the page, one row per person, without its totals row. Each
  # heading is paired with how its cell is read, so a column cannot be added to
  # the header and missed in the rows.
  #
  # Name and email are there only for a reader allowed to see them. Reading this
  # report does not carry that permission, and a callsign is how this
  # organisation names people, so a reader without either still gets a usable
  # export.
  def csv_rows
    signups = @report.show_signups

    columns = { "Callsign" => :callsign.to_proc }
    columns["Name"] = :name.to_proc if Current.can_view_pii?
    columns["Status"] = :status.to_proc
    columns["Email"] = :email.to_proc if Current.can_view_email?
    @report.years.each do |year|
      columns["#{year} Hours"] = ->(row) { helpers.hour_format(row.hours_for(year)) }
      columns["#{year} Sign-Ups"] = ->(row) { row.signups_for(year) } if signups
    end
    columns["Total Hours"] = ->(row) { helpers.hour_format(row.total_hours) }
    columns["Total Sign-Ups"] = :total_signups.to_proc if signups

    [columns.keys, *@report.rows.map { |row| columns.values.map { |cell| cell.call(row) } }]
  end
end
