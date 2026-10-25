# frozen_string_literal: true

# Alpha Sign-Out (upstream Ember mentor/alpha-signout). Pick an Alpha shift,
# see every Alpha still on duty in the window around it, and end those shifts in
# one action. The command logic lives in AlphaSignOut.
#
# Deliberate departures from upstream, settled when this page was specced (see
# .scratch/mentoring-alpha-signout/PLAN.md):
#
#   * Not year-scoped, unlike Shift Report and Alpha Schedule: the page ends
#     shifts that are open right now, so a past year's Alpha shift could never
#     have anyone to sign out. Current.year is pinned, as on Alpha Status and
#     Convert Alphas, and upstream loads its own slot list for the current year
#     alone.
#   * Upstream gates the page on isMentor but its signoff endpoint on Shift
#     Management, so a Mentor without that role could open the page and watch
#     every sign-out fail. Here the two gates are separate and the button is
#     absent, not broken, without the write role.
#   * SHIFT_MANAGEMENT_SELF, which upstream's policy also accepts, is the
#     self-serve role -- it should not let someone end another person's shift.
#     The pair used here matches Person::TimesheetsController#signoff.
class Mentoring::AlphaSignoutController < ApplicationController
  layout "mentoring"

  before_action :setup_year

  # Upstream Gate isMentor.
  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to open Alpha Sign-Out."

  # Backs both the POST guard and the can?(:sign_out_alphas) affordance the view
  # reads, so the button and the guard cannot drift.
  authorize_ability :sign_out_alphas,
                    roles: [Role::SHIFT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT],
                    only: %i[sign_out],
                    deny_to: :signout_return_path,
                    message: "Shift Management role required to sign out Alphas."

  def index
    @results = {}
    @now_active = []
    load_roster
  end

  # Renders the roster again instead of redirecting, like Convert Alphas: a GET
  # cannot re-derive which rows were just ended, because they are no longer on
  # duty and so no longer on the list the page is built from. The house 422
  # results pattern, with the just-ended rows held in place one last time.
  def sign_out
    ids = IdList.parse(params.permit(entry_ids: [])[:entry_ids])

    if ids.empty?
      return redirect_to signout_return_path, alert: "Check at least one Alpha to sign out."
    end

    outcome = AlphaSignOut.sign_out(ids, user: current_user)
    @results = outcome.results
    @now_active = outcome.now_active
    load_roster(keep_ids: ids)

    render :index, status: :unprocessable_entity
  end

  private

  # Pinned, not read from params -- see the class comment.
  def setup_year
    @year = Current.year
  end

  # Which shift (or which mode) the reader is on rides in the query string on a
  # GET and in the form on the POST, so both arrive here the same way.
  def load_roster(keep_ids: [])
    if params[:on_duty].present?
      @mode = :everywhere
      @roster = AlphaSignOut.on_duty_everywhere(keep_ids:)
    elsif params[:slot_id].present?
      load_slot_roster(keep_ids)
    end

    # The picker is a whole card grid, so the roster replaces it rather than
    # sitting under it. Only built when there is no roster to show.
    @shifts = pickable_shifts if @roster.nil?
  end

  # Upstream 422s on a slot that is missing or not the Alpha position; here a bad
  # id keeps the picker on screen with an error. Looked up across all years on
  # purpose -- a bookmarked link must keep meaning the same shift. Inactive slots
  # fall through to the error, matching the picker, which drops them.
  def load_slot_roster(keep_ids)
    @slot = Slot.active.where(position_id: Position::ALPHA).find_by(id: params[:slot_id])
    unless @slot
      flash.now[:error] = "That shift is not an Alpha shift this page covers. Pick a shift from the list."
      return
    end

    @mode = :slot
    @roster = AlphaSignOut.for_slot(@slot, keep_ids:)
  end

  # Inactive shifts are dropped rather than badged (the Alpha Schedule keeps
  # them): load_slot_roster refuses them, so an inactive card would open an
  # error.
  def pickable_shifts
    AlphaShiftRoster.shifts_for_year(@year).select { |shift| shift.slot.active }
  end

  # Keeps a refused or empty submission on the shift the reader was looking at
  # rather than dropping them back to the picker.
  def signout_return_path
    if params[:on_duty].present?
      mentoring_alpha_signout_path(on_duty: 1)
    elsif params[:slot_id].present?
      mentoring_alpha_signout_path(slot_id: params[:slot_id])
    else
      mentoring_alpha_signout_path
    end
  end
end
