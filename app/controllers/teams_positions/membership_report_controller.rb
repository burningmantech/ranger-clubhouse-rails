# frozen_string_literal: true

class TeamsPositions::MembershipReportController < ApplicationController
  layout "teams_positions"

  # Upstream's TeamPolicy asks for Event Management alone -- Laravel's hasRole
  # has no Admin shortcut -- and every report ported into this app names Admin
  # alongside it. Read-only either way: nothing here writes.
  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT],
                 message: "Admin or Event Management role required to view the membership report."

  before_action :set_team, only: :show

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # The manager and sort tokens live on TeamsPositions::MembershipReportHelper,
  # which owns their labels, and are named in full inside methods rather than
  # aliased to a constant here -- a class-body constant reference resolves at
  # load time, and a controller/helper pair that names each other that way
  # deadlocks both autoloads. Reading the label hashes' keys also means a token
  # cannot be accepted here without having a label to draw.

  # Only active teams, matching upstream's Team::findAll(true). The three
  # inactive ones are records, not rosters -- Team Records is where they live.
  def index
    active = Team.where(active: true).order(:title)

    @total_count = active.count
    # Both hashes cover every active team, not just the filtered ones: the stat
    # boxes, the manager filter, and the count sorts all read them, so they
    # cannot disagree about which teams are short a manager.
    @member_counts = membership_counts(PersonTeam, active)
    @manager_counts = membership_counts(TeamManager, active)

    @filter_params = filter_params
    @return_params = current_index_params
    @teams = apply_filters(active)

    # Every rollup describes the teams actually listed, not the whole report --
    # they sit in one summary line directly above those rows, and a line that
    # mixed filtered counts with report-wide ones would be read as describing
    # what is on screen.
    @membership_count = @teams.sum { |team| @member_counts[team.id].to_i }
    @people_count = PersonTeam.where(team_id: @teams.map(&:id)).distinct.count(:person_id)
    @missing_manager_count = @teams.count { |team| unmanaged?(team) }
  end

  def show
    @members = people_for(PersonTeam)
    @managers = people_for(TeamManager)
    @return_params = current_index_params
  end

  private

  # An inactive team is off the report by definition, so its roster page would
  # contradict the index it was reached from. A stale bookmark lands back on the
  # list with the reason rather than on a 404 that explains nothing.
  def set_team
    @team = Team.find(params[:team_id])
    return if @team.active

    redirect_to teams_positions_membership_report_path,
                warning: "#{@team.title} is no longer an active team, so it is not on this report."
  end

  # {team_id => count} across every active team.
  def membership_counts(model, active)
    model.where(team_id: active.select(:id)).group(:team_id).count
  end

  # The people themselves, ordered by MySQL's own case-insensitive collation --
  # a Ruby sort_by here would file every lowercase callsign after "Zulu".
  # Queried through Person rather than the join model so basic_info's three
  # columns are all that cross the wire, and loaded up front so asking for the
  # count does not cost a second round trip.
  def people_for(model)
    Person.basic_info
          .where(id: model.where(team_id: @team.id).select(:person_id))
          .order(:callsign)
          .to_a
  end

  def filter_params
    {
      type: UiComponents::FilterBarHelper.known_filter(params[:type], TeamManagement::TYPES),
      managers: UiComponents::FilterBarHelper.known_filter(params[:managers], TeamsPositions::MembershipReportHelper::MANAGER_LABELS.keys),
      sort: UiComponents::FilterBarHelper.known_filter(params[:sort], TeamsPositions::MembershipReportHelper::SORT_LABELS.keys),
      title: params[:title].is_a?(String) ? params[:title].strip.presence : nil
    }
  end

  # Type and title narrow in SQL; the manager filter and the count sorts run in
  # Ruby against the hashes above. Splitting them that way is deliberate -- the
  # alternative is a second COUNT subquery that could drift from the stat boxes,
  # and the whole list is 61 rows.
  def apply_filters(teams)
    teams = teams.where(type: @filter_params[:type]) if @filter_params[:type] != ALL
    title = @filter_params[:title]
    teams = teams.where_like("title", "%#{Team.sanitize_sql_like(title)}%") if title

    # Only the three columns the table draws: team carries a longtext
    # description no page here renders, and it would ride along on all 61 rows.
    # Narrowed here rather than on the base scope, which is reused as the
    # `select(:id)` subquery above -- select APPENDS, so narrowing it there
    # yields a multi-column subquery and MySQL rejects the whole query.
    sort_teams(filter_by_managers(teams.select(:id, :title, :type).to_a))
  end

  def filter_by_managers(teams)
    case @filter_params[:managers]
    when TeamsPositions::MembershipReportHelper::MANAGERS_MISSING
      teams.select { |team| unmanaged?(team) }
    when TeamsPositions::MembershipReportHelper::MANAGERS_PRESENT
      teams.reject { |team| unmanaged?(team) }
    else teams
    end
  end

  def unmanaged?(team) = @manager_counts[team.id].to_i.zero?

  # Ties keep the title order the query arrived in -- Ruby's sort_by is not
  # stable on its own, so the original index rides along as the tiebreaker.
  def sort_teams(teams)
    counts, direction = case @filter_params[:sort]
                        when TeamsPositions::MembershipReportHelper::SORT_MEMBERS then [@member_counts, -1]
                        when TeamsPositions::MembershipReportHelper::SORT_MANAGERS then [@manager_counts, 1]
                        else return teams
                        end

    teams.sort_by.with_index { |team, index| [direction * counts[team.id].to_i, index] }
  end

  # The filters the reader was working in, carried onto the roster page so Back
  # returns them to the list they came from. active_filters already drops blanks
  # and the "all" sentinel, so nothing further is needed to clean the hash.
  def current_index_params
    UiComponents::FilterBarHelper.active_filters(filter_params)
  end
end
