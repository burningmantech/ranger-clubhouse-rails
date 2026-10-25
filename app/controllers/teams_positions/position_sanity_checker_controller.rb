# frozen_string_literal: true

# Position, team, and role grants that contradict each other (Ember
# admin/position-sanity-checker port). Upstream stacked nine collapsed
# accordions, each holding a table and its own repair form, on one page; the
# index here is a triage board and each check drills into its own page.
class TeamsPositions::PositionSanityCheckerController < ApplicationController
  layout "teams_positions"

  # Upstream's Ember route admits Admin and Event Management, but
  # PositionPolicy::before admits Admin and Tech Ninja alone -- an Event
  # Management reader reached the page and was refused by every request it
  # made. The API is the authority, so the menu link and the page agree on it.
  #
  # The same gate covers repairs, which is why there is no read-only mode: a
  # reader who can see these findings can settle them.
  authorize_role [Role::ADMIN, Role::TECH_NINJA],
                 message: "Admin or Tech Ninja role required to view the position sanity checker."

  UNKNOWN_CHECK = "That sanity check does not exist."

  # As many findings as one form can usefully carry. A misconfigured position
  # -- one All Rangers flag on a position no one holds -- puts the whole roster
  # on Accounts Missing Basic Positions, and a thousand-row page with a select-
  # all control is neither a worklist nor a request that finishes: past Rack's
  # 4,096-parameter limit the POST is refused outright with nothing to show for
  # it. Repairing the visible page and reloading walks the list down.
  PAGE_LIMIT = 250

  before_action :set_check, only: %i[check repair]

  def index
    @counts = PositionSanityCheck.counts
  end

  def check
    load_findings
  end

  # Settle the selected findings and show what happened.
  #
  # Renders rather than redirects, and at 422 so Turbo accepts it: what the
  # repair did is not something the check page can re-derive once the rows it
  # fixed have stopped being findings.
  def repair
    @results, @skipped = @checker.repair(params.permit(keys: [])[:keys])
    load_findings

    render :check, status: :unprocessable_entity
  end

  private

  # One over the cap, so the overflow is visible without a second pass over the
  # check to count it.
  def load_findings
    @findings = @checker.findings
    @truncated = @findings.size > PAGE_LIMIT
    @findings = @findings.first(PAGE_LIMIT) if @truncated
  end

  # Validated against the registry's key list, which is the set the checks
  # dispatch on. An unrecognized key is a stale bookmark rather than an
  # exception, so it lands back on the index with a reason.
  def set_check
    key = params[:check].to_s.underscore
    @checker = PositionSanityCheck.checker(key)
    return redirect_to(teams_positions_position_sanity_checker_path, error: UNKNOWN_CHECK) unless @checker

    # Interned only after the registry has vouched for it, so a crafted URL
    # cannot mint symbols.
    @check = key.to_sym
  end
end
