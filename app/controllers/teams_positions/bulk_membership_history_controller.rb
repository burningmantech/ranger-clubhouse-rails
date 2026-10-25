# frozen_string_literal: true

# Recording when people joined and left a team, for a list of callsigns at once.
#
# The Team Membership group of upstream's admin/bulk-upload. It writes
# person_team_log and nothing else: this is the record of who was on a team and
# when, not the roster of who is on it now. Bulk Grant / Revoke a Team owns the
# roster, and the advisory above the form says so, because the two read alike
# from the menu and only one of them changes anything today.
#
# Not year_scoped: a history row carries the dates it was given, so nothing here
# lands in the event year the reader happens to be looking at.
class TeamsPositions::BulkMembershipHistoryController < ApplicationController
  include BulkUploadPage

  layout "teams_positions"

  # No authorize_role, for the same reason the sibling bulk pages have none: the
  # gate is a role or a per-team row, which a flat role list cannot express.
  # Leaving authorized_roles nil lets the role gatekeeper pass so this
  # before_action can answer instead.
  #
  # Unconditional rather than `only:` -- with nothing for the gatekeeper to
  # enforce, an action added later would otherwise ship with no authorization.
  before_action :require_history_recorder
  before_action :set_team, only: %i[preview apply]

  helper_method :manageable_teams

  bulk_upload_page title: "Bulk Record Team Membership History",
                   icon: "clock-rotate-left",
                   description: "Record when people joined and left one team.",
                   action_label: "What to record",
                   action_prompt: "Choose what to record",
                   records_label: "Callsigns and dates",
                   records_help: "One person per line: callsign, the date they joined, and — if " \
                                 "they have left — the date they left. Dates are YYYY-MM-DD. " \
                                 "For example: hubcap,2024-08-01,2024-09-05",
                   extra_params: [:team_id]

  # One action, still offered through a select rather than assumed: upstream
  # calls this group Team Membership and has room for more in it, and the next
  # thing recorded here arrives as a second line in this list with nothing else
  # about the page changing.
  #
  # The id keeps upstream's spelling, so the action_log rows the two
  # applications write stay searchable together.
  ACTIONS = [
    BulkUpload::Action.new(id: "team_membership",
                           label: "Add Team Membership History",
                           help: "callsign,joined on[,left on]",
                           handler: BulkUpload::MembershipHistoryHandler)
  ].freeze

  private

  def bulk_actions = ACTIONS

  # The team the handler writes against. Set by a before_action that has already
  # refused anything the reader cannot reach, so the handler never re-checks it.
  def batch_context = { team: @team }

  # An Admin, or anyone holding a team_manager row.
  #
  # Deliberately not Team.manageable_by?, which the sibling bulk pages use: that
  # predicate also demands Event Management, and would refuse a plain Clubhouse
  # Team Manager -- who is exactly the person this page is for. The wider gate is
  # safe here because a history row confers nothing: no membership, no position,
  # no role. The pages that do confer those keep the narrower gate.
  def require_history_recorder
    return if is_admin? || is_team_manager?

    not_authorized_redirect("Recording team membership history needs the Admin role, " \
                            "or a team to manage.")
  end

  # The teams this person may record history for: an Admin reaches every team,
  # and everyone else reaches only the teams they hold a team_manager row for.
  #
  # Deliberately NOT Team.manages_every_team?, which also admits Tech Ninja.
  # That predicate is wider than the gate above, and pairing the two made
  # reachability incoherent: a Tech Ninja holding no team_manager row was
  # refused the page outright, while one who happened to manage a single team
  # was handed write access to every team's history. The gate and the scope now
  # answer the same question.
  #
  # No guarded-team filter, unlike Bulk Teams: that page leaves out teams
  # conferring Admin or Tech Ninja because granting one hands the role to
  # everybody on the list. Recording that someone was on the team in 2019 hands
  # out nothing, so leaving those teams out would only make their history
  # unrecordable.
  #
  # Team rows rather than TeamManager.retrieve_teams_for_person's {id:, title:}
  # hashes: the select's inactive marker and set_team's lookup both need the
  # record itself, and one relation orders in the database rather than in Ruby.
  def manageable_teams
    @manageable_teams ||= team_scope.order(:title).to_a
  end

  def team_scope
    return Team.all if is_admin?

    Team.where(id: TeamManager.retrieve_team_ids_for_person(Current.person_id))
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
end
