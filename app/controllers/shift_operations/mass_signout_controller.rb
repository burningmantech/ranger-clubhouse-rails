# frozen_string_literal: true

# Sign out everyone still on duty in one sweep (Ember admin/bulk-signout port).
#
# Upstream fired one POST timesheet/{id}/signoff per selected row from the
# browser, with a per-row spinner. Here it is one form post and one pass over
# the selected entries; the spinner existed only because each row was a round
# trip.
class ShiftOperations::MassSignoutController < ApplicationController
  layout "shift_operations"

  # Admin only, matching the upstream menu item, which sits inside the
  # `{{#if (has-role "admin")}}` block of navbar-area-admin.hbs.
  #
  # TimesheetPolicy@signoff is looser -- it admits Shift Management and even
  # Shift Management Self, which lets a self-serve user close anyone's entry.
  # That is the per-row API contract behind the HQ window, not this page's:
  # nothing here signs out one named Ranger, it sweeps the whole board.
  authorize_role [Role::ADMIN],
                 message: "Admin role required to sign Rangers out in bulk."

  def index
    @report = MassSignoutReport.execute
  end

  def create
    ids = requested_ids

    if ids.empty?
      return redirect_to shift_operations_mass_signout_path,
                         error: "Select at least one Ranger to sign out."
    end

    # MassSignoutReport.selectable, not a second query spelled here: it re-derives
    # "still open" against the very scope the page was drawn from, so HQ closing
    # a row between render and submit drops it silently, and a hand-edited form
    # cannot reach an entry that was never open.
    #
    # Stale entries are NOT refused -- by design the guard against them is the
    # unchecked box and the callout, not a ban. A deliberate hand-check still works.
    entries, unsignable = MassSignoutReport.selectable(ids)
    signed, converted = sign_off_all(entries)

    # A sweep that closed nothing is not a success, however it reads: green on
    # "0 Rangers signed out" tells an admin the board is clear when it is not.
    flash_type = signed.zero? ? :warning : :success
    redirect_to shift_operations_mass_signout_path,
                flash_type => outcome_message(signed, converted, ids.size, unsignable.size)
  end

  private

  # The house spelling -- alpha_signout, alphas_convert, and convert_prospectives
  # all reduce a checkbox id list this way. permit(ids: []) returns nil for the
  # shapes an unpermitted key can arrive in (`?ids[a]=b` as Parameters, `?ids=5`
  # as a String), so both collapse to [] and land on "select at least one".
  def requested_ids
    IdList.parse(params.permit(ids: [])[:ids])
  end

  # No transaction: each signoff is independently meaningful, one of them may
  # send a status-conversion email, and a failure on the fifth entry must not
  # undo the first four. Upstream is per-row for the same reason.
  def sign_off_all(entries)
    signed = 0
    converted = []

    entries.each do |entry|
      result = ShiftManage.sign_off(entry, user: current_user)
      next unless result.status == :success

      signed += 1
      converted << entry.person.callsign if result.now_active
    end

    [signed, converted]
  end

  # Status conversion is a side effect no one asked for, so it is named rather
  # than left to be discovered. A short count means those entries were no longer
  # open by the time the form arrived -- worth saying out loud on a page whose
  # whole purpose is to leave the board empty.
  #
  # "no longer open", not "already signed out": the shortfall also covers an id
  # whose entry was deleted, and one that never existed at all.
  def outcome_message(signed, converted, requested, unsignable)
    message = +"#{helpers.pluralize(signed, "Ranger")} signed out."

    if converted.any?
      message << " #{converted.to_sentence} #{(converted.size == 1) ? "was" : "were"} " \
                 "converted back to Active."
    end

    if unsignable.positive?
      message << " #{helpers.pluralize(unsignable, "entry")} could not be signed out — " \
                 "the Ranger's record is gone."
    end

    missed = requested - signed - unsignable
    if missed.positive?
      message << " #{helpers.pluralize(missed, "entry")} #{(missed == 1) ? "was" : "were"} " \
                 "no longer open."
    end

    message
  end
end
