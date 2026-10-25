# frozen_string_literal: true

class TeamsPositions::BulkPositionsController < ApplicationController
  layout "teams_positions"

  # No authorize_role here, for the same reason Roster Management has none: the
  # gate is a role that opens the page at all and then a per-position check,
  # which a flat role list cannot express. Leaving authorized_roles nil lets the
  # role gatekeeper pass so this before_action can answer instead.
  #
  # Unconditional rather than `only:` -- with nothing for the gatekeeper to
  # enforce, an action added later would otherwise ship with no authorization.
  before_action :require_position_manager
  before_action :set_position, only: %i[preview apply]

  # Grant and revoke are separate values rather than a boolean, so a missing
  # radio cannot be read as "revoke".
  DIRECTIONS = { "grant" => true, "revoke" => false }.freeze

  helper_method :manageable_positions

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

  # Step two: rebuild the change from this request's own params, re-check the
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

  def require_position_manager
    return if Team.manageable_by?(Current.person)

    not_authorized_redirect("Bulk position changes need the Event Management or Admin role, " \
                            "and a team to manage.")
  end

  # The positions this person may grant or revoke here. An Admin or Tech Ninja
  # reaches every position, including the team-less ones; everyone else reaches
  # the positions of the teams they hold a team_manager row for. Upstream draws
  # the same two lines in Position::findForQuery's can_manage join.
  def manageable_positions
    @manageable_positions ||= reject_guarded(position_scope.includes(:team).order(:title).to_a)
  end

  def position_scope
    return Position.all if Team.manages_every_team?(Current.person)

    Position.where(team_id: TeamManager.retrieve_team_ids_for_person(Current.person.id))
  end

  # A position whose grant carries Admin or Tech Ninja is not offered to anyone
  # who does not already hold that role, in either direction: handing out a role
  # and taking one away are both moving a real permission, and Roster Management
  # guards the mirror operation the same way.
  #
  # This is the narrower of the two guards. Upstream refuses to GRANT such a
  # position through this endpoint at all, for every user including an Admin
  # (PositionController#bulkGrantRevoke tests the direction, never the actor),
  # so `refuse_guarded_grant` below keeps that ban and this filter only decides
  # who may revoke. Filtered here rather than refused on submit so an
  # unreachable choice is never offered.
  def reject_guarded(positions)
    guarded = PositionRole.where(position_id: positions.map(&:id),
                                 role_id: TeamManagement::GUARDED_ROLE_IDS)
                          .pluck(:position_id, :role_id)
                          .reject { |_position_id, role_id| Current.person.has_role?(role_id) }
                          .map(&:first).to_set

    positions.reject { |position| guarded.include?(position.id) }
  end

  # Scoped rather than found-then-checked, so an unreachable position and a
  # nonexistent one answer identically. `to_s` first because a param can arrive
  # array- or hash-shaped, and neither answers to_i -- a gate that raises
  # instead of denying is the wrong failure mode.
  def set_position
    @position = manageable_positions.find { |position| position.id == params[:position_id].to_s.to_i }
    return if @position

    refuse("Choose a position from the list.")
  end

  # Returns the change, or nil having already re-rendered the form.
  def build_change
    return refuse("Choose whether to grant or revoke the position.") unless DIRECTIONS.key?(params[:direction])

    grant = DIRECTIONS.fetch(params[:direction])
    return nil if grant && refuse_guarded_grant

    change = TeamManagement::BulkPositionChange.new(
      position: @position, grant:, callsigns: params[:callsigns]
    )
    return refuse("Enter at least one callsign, one per line.") if change.entries.empty?

    change
  end

  # Upstream's ban, kept: no one hands out Admin or Tech Ninja to a pasted list,
  # however senior they are. A single mistaken or borrowed session should not be
  # able to make two hundred admins in one POST. Revoking is still allowed, to
  # whoever holds the role themselves.
  def refuse_guarded_grant
    return false unless PositionRole.exists?(position_id: @position.id,
                                             role_id: TeamManagement::GUARDED_ROLE_IDS)

    refuse("#{@position.title} grants the Admin or Tech Ninja role. Positions that carry those " \
           "roles cannot be handed out here — grant them one at a time from the person's page.")
    true
  end

  # Re-renders rather than redirects: a redirect would drop the pasted list, and
  # re-typing it is the whole cost of getting this page wrong.
  def refuse(message)
    flash.now[:error] = message
    render :index, status: :unprocessable_entity
    nil
  end
end
