# frozen_string_literal: true

class TeamsPositions::BulkTeamsController < ApplicationController
  layout "teams_positions"

  # No authorize_role here, for the same reason Bulk Positions and Roster
  # Management have none: the gate is a role that opens the page at all and then
  # a per-team check, which a flat role list cannot express. Leaving
  # authorized_roles nil lets the role gatekeeper pass so this before_action can
  # answer instead.
  #
  # Unconditional rather than `only:` -- with nothing for the gatekeeper to
  # enforce, an action added later would otherwise ship with no authorization.
  before_action :require_team_manager
  before_action :set_team, only: %i[preview apply]

  # Grant and revoke are separate values rather than a boolean, so a missing
  # radio cannot be read as "revoke".
  DIRECTIONS = { "grant" => true, "revoke" => false }.freeze

  helper_method :manageable_teams

  # Also the target of the "edit" POST: renders the form with whatever params
  # arrived, so a correction after a preview keeps the pasted list. Turbo drops
  # a 200 answer to a form submission, so that POST has to leave as 422 or the
  # button does nothing; the plain GET stays 200.
  def index
    render status: :unprocessable_entity if request.post?
  end

  # Step one: show exactly what would change, and write nothing.
  def preview
    @change = build_change
    return unless @change

    render :preview, status: :unprocessable_entity
  end

  # Step two: rebuild the change from this request's own params, re-check every
  # gate, then write. Nothing computed by the preview is trusted here.
  #
  # Renders rather than redirects, for the reason `refuse` does: a redirect
  # drops the pasted list, and the report of what just happened would survive
  # only as a toast that clips a long list and then dismisses itself.
  def apply
    @change = build_change
    return unless @change

    @outcome = @change.apply!
    render :index, status: :unprocessable_entity
  end

  private

  def require_team_manager
    return if Team.manageable_by?(Current.person)

    not_authorized_redirect("Bulk team changes need the Event Management or Admin role, " \
                            "and a team to manage.")
  end

  # The teams this person may grant or revoke here. An Admin or Tech Ninja
  # reaches every team; everyone else reaches the teams they hold a team_manager
  # row for. Team.manageable_by is the single authority, shared with Roster
  # Management and the menu's visibility rule.
  def manageable_teams
    @manageable_teams ||= reject_guarded(Team.manageable_by(Current.person).order(:title).to_a)
  end

  # A team whose own membership confers Admin or Tech Ninja is not offered to
  # anyone at all, in either direction. Upstream refuses those teams outright
  # (TeamController#bulkGrantRevoke raises before the work begins, for every
  # user including an Admin), and that ban is kept: a single mistaken or
  # borrowed session should not be able to make two hundred admins in one POST.
  # Those memberships are moved one at a time from the person's page.
  #
  # Filtered here rather than only refused on submit, so an unreachable choice
  # is never offered.
  def reject_guarded(teams)
    guarded = TeamRole.where(team_id: teams.map(&:id), role_id: TeamManagement::GUARDED_ROLE_IDS)
                      .pluck(:team_id).to_set

    teams.reject { |team| guarded.include?(team.id) }
  end

  # Scoped rather than found-then-checked, so an unreachable team and a
  # nonexistent one answer identically. `to_s` first because a param can arrive
  # array- or hash-shaped, and neither answers to_i -- a gate that raises
  # instead of denying is the wrong failure mode.
  def set_team
    @team = manageable_teams.find { |team| team.id == params[:team_id].to_s.to_i }
    return if @team

    refuse("Choose a team from the list.")
  end

  # Returns the change, or nil having already re-rendered the form.
  def build_change
    return refuse("Choose whether to grant or revoke the team.") unless DIRECTIONS.key?(params[:direction])

    change = TeamManagement::BulkTeamChange.new(
      team: @team, grant: DIRECTIONS.fetch(params[:direction]), callsigns: params[:callsigns]
    )
    return nil if refuse_guarded_positions(change)
    return refuse("Enter at least one callsign, one per line.") if change.entries.empty?

    change
  end

  # The team itself is already known not to confer a guarded role -- that is the
  # ban above -- but one of the positions it carries with the membership still
  # can, and granting the team hands that position to everyone on the list.
  #
  # Granting is therefore refused outright, for every actor including an Admin,
  # exactly as the sibling page refuses it (BulkPositionsController's
  # refuse_guarded_grant tests the direction, never the actor). Without that the
  # ban stated on reject_guarded above would be trivially bypassable: pick the
  # team rather than the position and the same two hundred admins get made in
  # the same one POST. This page is wider than Roster Management, whose grid is
  # bounded to people already on the roster -- here any callsign in the
  # organization can be pasted in.
  #
  # Revoking is still allowed to whoever holds the role themselves, which is the
  # rule Roster Management applies to the mirror operation.
  #
  # Checked here rather than left to PersonPosition.add_ids_to_person, which
  # raises per person: without it every line of a confirmed list would land in
  # `failed` and the reader would be told to read the log to find out why. The
  # revoke path has no model-level check at all, so for that direction this is
  # the only gate.
  #
  # Not filtered out of the team list, because which positions move depends on
  # the direction -- a grant carries only the Recommended ones -- and a select
  # drawn before the direction is chosen cannot say which teams are reachable.
  def refuse_guarded_positions(change)
    # Filtered in SQL and answered from the ids themselves. Asking whether a
    # `role` ROW comes back would fail OPEN: position_role carries no foreign
    # key to role, so a position naming a role id with no row would sail past a
    # guard keyed on Role.where(...).any?. Role is consulted only for titles.
    blocked = PositionRole.where(position_id: change.position_ids,
                                 role_id: TeamManagement::GUARDED_ROLE_IDS)
                          .distinct.pluck(:role_id)
    return false if blocked.empty?

    return refuse_guarded_grant(change, blocked) if change.grant?

    held = blocked.reject { |role_id| Current.person&.has_role?(role_id) }
    return false if held.empty?

    refuse("#{change.team.title} carries #{role_titles(held)} through its positions, " \
           "and you do not hold #{held.many? ? "them" : "it"} yourself.")
    true
  end

  def refuse_guarded_grant(change, blocked)
    refuse("#{change.team.title} grants #{role_titles(blocked)} through its positions. Teams " \
           "carrying those roles cannot be handed out here — add people one at a time from " \
           "their own page.")
    true
  end

  # Named without trusting the row to exist, for the same reason the check above
  # does not. TeamManagement.validate_roles falls back the same way.
  def role_titles(role_ids)
    titles = Role.where(id: role_ids).pluck(:id, :title).to_h

    role_ids.sort.map { |role_id| titles[role_id] || "Role ##{role_id}" }.to_sentence
  end

  # Re-renders rather than redirects: a redirect would drop the pasted list, and
  # re-typing it is the whole cost of getting this page wrong.
  def refuse(message)
    flash.now[:error] = message
    render :index, status: :unprocessable_entity
    nil
  end
end
