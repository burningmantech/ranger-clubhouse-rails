# frozen_string_literal: true

# Sign a pasted list of Rangers in and/or out (Ember ops/bulk-sign-in-out port).
#
# The four-step shape every bulk page in the application uses -- form, preview
# that writes nothing, apply, and a POST back to the form -- but not the
# BulkUploadPage concern: that concern is built around a select of named actions
# over a list of callsigns, and this page has one action inferred per line
# instead. Sharing it would mean overriding nearly all of it.
#
# Where this page really differs from the bulk-upload family is the commit rule:
# there, a batch with problems still commits its clean rows. Here one bad line
# stops everything. Upstream works that way and it suits the payload -- these
# lines are timesheets, and a half-applied paste leaves an HQ worker guessing
# which Rangers still need doing.
class ShiftOperations::BulkSignInOutController < ApplicationController
  layout "shift_operations"

  # The upstream Ember route asks for Admin or Timesheet Management; the API
  # policy behind it checks Timesheet Management alone (Admin passes everything).
  authorize_role [Role::ADMIN, Role::TIMESHEET_MANAGEMENT],
                 message: "Timesheet Management role required to sign Rangers in or out in bulk."

  # The form. Also the target of the "edit" POST from the preview, which
  # re-renders it with the pasted list intact.
  def index
    render :index, status: request.post? ? :unprocessable_entity : :ok
  end

  # Show exactly what would happen, and write nothing.
  def preview
    return unless parse_lines

    render :preview, status: :unprocessable_entity
  end

  # Re-parse from this request's own params and re-run every check, then write.
  # Nothing the preview computed is trusted here -- it described the change, it
  # did not authorize it, and a Ranger may have signed in or out in between.
  def apply
    return unless parse_lines

    # All-or-nothing. A hand-posted apply lands here too, so this is the
    # enforcement and the missing commit button is only the courtesy.
    return render :preview, status: :unprocessable_entity if @have_error

    @have_error = BulkSignInOut.process(@entries, user: current_user)

    if @have_error
      # A write that failed after its checks passed -- the entry carries the
      # reason, so the review table is still the right place to read it.
      return render :preview, status: :unprocessable_entity
    end

    ActionLog.record(current_user, "bulk-sign-in-out", "",
                     { lines: params[:lines], processed: @entries.map(&:to_log) })

    @committed = true
    render :index, status: :unprocessable_entity
  end

  private

  # Parses params[:lines] into @entries/@have_error, or re-renders the form
  # having refused an empty list. Returns false when it refused.
  #
  # One guard, not two: parse answers [[], false] for a missing param as well as
  # for a list of nothing but blank lines, so an empty result covers both.
  def parse_lines
    @entries, @have_error = BulkSignInOut.parse(params[:lines])
    return true if @entries.any?

    flash.now[:error] = "Enter at least one line."
    render :index, status: :unprocessable_entity
    false
  end
end
