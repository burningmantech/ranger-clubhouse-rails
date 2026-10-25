# frozen_string_literal: true

class TeamsPositions::RosterManagementController < ApplicationController
  layout "teams_positions"

  # No authorize_role here. The gate is two-part -- a role that opens the page
  # at all, and then a per-team check -- which a flat role list cannot express,
  # and leaving authorized_roles nil lets the role gatekeeper pass so these
  # before_actions can answer it. Team::ROSTER_ACCESS_ROLES and
  # Team.manageable_by are the single authority, shared with the menu's
  # visibility rule.
  #
  # The first gate is unconditional rather than `only: :index`: with no
  # authorized_roles for the gatekeeper to enforce, an action added later would
  # otherwise ship with no authorization at all. set_team then narrows it to the
  # one team, for the actions that name one.
  before_action :require_roster_manager
  before_action :set_team, only: %i[show preview apply]

  def index
    @teams = Team.manageable_by(Current.person).order(:title).to_a
    @manages_all = Team.manages_every_team?(Current.person)
    @member_counts = PersonTeam.where(team_id: @teams.map(&:id)).group(:team_id).count
  end

  def show
    @report = report
    @filter_params = filter_params
    @return_params = active_filter_params
    @people = filtered_people
    @blocked_roles = guarded_roles_lacked(revocable_position_ids, include_team_roles: true)
  end

  # Step one of every bulk action: show exactly what would change, and write
  # nothing. Rendered from the POST rather than redirected to, because the
  # selected ids are not in the URL and a GET could not re-derive them.
  def preview
    @action = build_action
    return unless action_ready?(@action)

    @report = report
    @filter_params = filter_params
    @return_params = active_filter_params
    render :preview, status: :unprocessable_entity
  end

  # Step two: the confirmed action. Everything is re-derived and re-checked
  # here -- the preview's numbers are a promise about what this will do, not an
  # authority for doing it.
  def apply
    action = build_action
    return unless action_ready?(action)

    outcome = action.apply!(reason: "roster management, #{@team.title}")
    redirect_back_with(**outcome_flash(action, outcome))
  end

  private

  # The checks both steps share. Returns false having already redirected, so
  # the second step cannot be reached by posting straight past the preview.
  def action_ready?(action)
    return redirect_back_with(error: action) && false if action.is_a?(String)

    blocked = guarded_roles_lacked(action.position_ids, include_team_roles: action.remove_from_team?)
    return refuse_guarded(blocked) && false if blocked.any?

    if action.people.empty?
      redirect_back_with(error: "No one was selected. Check at least one person.")
      return false
    end

    true
  end

  # Scoped rather than found-then-checked: an unmanageable team and a
  # nonexistent one now answer identically, so the ids cannot be walked to read
  # back the title of every team, cadre, and delegation.
  def set_team
    @team = Team.manageable_by(Current.person).find_by(id: params[:team_id])
    return if @team

    not_authorized_redirect("That team's roster is not available to you.")
  end

  def require_roster_manager
    return if Team.manageable_by?(Current.person)

    not_authorized_redirect("Roster Management needs the Event Management or Admin role, " \
                            "and a team to manage.")
  end

  # Memoized: the filters, the action's person list, and the view all ask for
  # the same grid, and it is the page's one expensive query set.
  def report = @report ||= TeamMembershipReport.execute(@team)

  # ------------------------------------------------------------- filtering

  # Spelled here rather than read straight from params so a hand-edited URL
  # cannot ask for a filter this page does not apply.
  def filter_params
    helper = TeamsPositions::RosterManagementHelper

    {
      view: UiComponents::FilterBarHelper.known_filter(params[:view], helper::VIEW_LABELS.keys),
      position: UiComponents::FilterBarHelper.known_filter(params[:position], helper.position_filter_values(report)),
      year: UiComponents::FilterBarHelper.known_filter(params[:year], [helper::YEAR_NEVER] + report.activity_years.map(&:to_s)),
      status: UiComponents::FilterBarHelper.known_filter(params[:status], report.status_counts.keys),
      callsign: params[:callsign].to_s.strip
    }
  end

  # The filters worth carrying in a URL: "all" and an empty search narrow
  # nothing, and a link that spelled them would draw a chip promising it had.
  def active_filter_params = UiComponents::FilterBarHelper.active_filters(filter_params)

  # Filtering runs over the report's rows rather than the database: the grid is
  # already built and unpaginated, and every one of these asks a question about
  # grants the report has in hand.
  def filtered_people
    helper = TeamsPositions::RosterManagementHelper
    filters = @filter_params
    people = report.people

    people = people.select { |person| person.callsign.downcase.include?(filters[:callsign].downcase) } if filters[:callsign].present?
    people = people.select { |person| person.status == filters[:status] } if active?(filters[:status])
    people = apply_year_filter(people, filters[:year]) if active?(filters[:year])
    people = apply_position_filter(people, filters[:position]) if active?(filters[:position])

    categories = helper::NEVER_CATEGORIES[filters[:view]]
    return people unless categories

    position_ids = categories.flat_map { |category| report.position_ids_in(category) }
    people.reject { |person| person.rangered_any?(position_ids) }
  end

  def active?(value) = value.present? && value != UiComponents::FilterBarHelper::ALL_FILTER

  def apply_year_filter(people, year)
    return people.select { |person| person.last_year.nil? } if year == TeamsPositions::RosterManagementHelper::YEAR_NEVER

    people.select { |person| person.last_year == year.to_i }
  end

  def apply_position_filter(people, value)
    holds, position_id = TeamsPositions::RosterManagementHelper.parse_position_filter(value)

    people.select { |person| person.grant(position_id).present? == holds }
  end

  # ---------------------------------------------------------------- actions

  # Returns a RosterAction, or a String naming what was wrong with the request.
  def build_action
    type = params[:action_type].to_s
    return "That is not an action this page performs." unless RosterAction.type?(type)

    position = action_position(type)
    return "Choose a position first." if RosterAction::NEEDS_POSITION.include?(type) && position.nil?

    RosterAction.new(team: @team, type:, position:, people: selected_people,
                     revocable_position_ids:)
  end

  # Only the team's own positions, so a hand-posted id cannot reach a position
  # this page does not manage.
  def action_position(type)
    return nil unless RosterAction::NEEDS_POSITION.include?(type)

    Position.find_by(id: params[:position_id], team_id: @team.id)
  end

  # Only people the grid shows. A hand-posted id for someone with no tie to the
  # team would otherwise be acted on and reported as changed.
  def selected_people
    ids = IdList.parse(params.permit(person_ids: [])[:person_ids]).to_set

    report.people.select { |person| ids.include?(person.id) }
  end

  def revocable_position_ids
    @revocable_position_ids ||= TeamMembershipReport.revocable_position_ids(@team)
  end

  # The port of the API's Role::assertActorMayConfer, which it applies to
  # removal as well as granting (PersonTeam::removePerson). Team and position
  # role grants are real permissions: moving them moves the permission. No one
  # may take away -- or hand out -- a role they do not hold themselves, and
  # PersonTeam.add_person already refuses the mirror operation.
  #
  # Enforced here rather than in PersonTeam.remove_person because that method is
  # also how PersonStatusManagement clears memberships when someone is dismissed
  # or bonked: raising there would make a status change fail on a role-bearing
  # team.
  # include_team_roles: only a removal takes the membership away, and only the
  # membership carries the team's own role grants. Passed explicitly rather
  # than inferred from the position list, which would fold the team's roles
  # into a single-position action on a team that happens to have one position.
  def guarded_roles_lacked(position_ids, include_team_roles:)
    role_ids = PositionRole.where(position_id: position_ids).pluck(:role_id)
    role_ids |= TeamRole.where(team_id: @team.id).pluck(:role_id) if include_team_roles

    Role.where(id: role_ids & TeamManagement::GUARDED_ROLE_IDS)
        .reject { |role| Current.person&.has_role?(role.id) }
  end

  def refuse_guarded(blocked)
    redirect_back_with(error: "That would move #{blocked.map(&:title).to_sentence}, " \
                              "and you do not hold it yourself.")
  end

  def redirect_back_with(**flash_message)
    redirect_to teams_positions_roster_management_team_path(@team, **active_filter_params), **flash_message
  end

  def outcome_flash(action, outcome)
    if outcome.changed.empty? && outcome.failed?
      return { error: "Nothing changed. #{callsigns(outcome.failed)} failed (#{outcome.reasons.join("; ")})." }
    end
    return { info: "Nothing to do -- no one selected needed that change." } if outcome.changed.empty?

    done = "#{action_verb(action)} #{callsigns(outcome.changed)}"
    return { success: "#{done}." } unless outcome.failed?

    { error: "#{done}, but #{callsigns(outcome.failed)} failed (#{outcome.reasons.join("; ")})." }
  end

  def action_verb(action)
    case action.type
    when RosterAction::GRANT_POSITION then "Granted #{action.position.title} to"
    when RosterAction::REVOKE_POSITION then "Revoked #{action.position.title} from"
    else "Removed from #{@team.title}:"
    end
  end

  def callsigns(people) = people.map(&:callsign).join(", ")
end
