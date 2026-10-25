# frozen_string_literal: true

# Seasonal ticketing maintenance tasks (Ember vc/access-documents/maintenance
# port). The Ember page confirmed with a modal and fired the POST; here every
# task follows the house index -> preview -> commit flow instead: the index
# only links to previews, each preview is a full dress rehearsal of its task
# (same selection, nothing saved), and the mutating POST lives only on the
# preview page.
#
# Task definitions live in TicketingMaintenance; this controller just
# dispatches on the slug.
#
# The commit renders its ledger with a 422: the results are transient (a GET
# cannot re-derive what just changed) and Turbo silently drops a 200 form
# response. Matches Vc::MaintenanceController.
class Ticketing::MaintenanceController < ApplicationController
  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to run ticketing maintenance."

  def index
    @groups = TicketingMaintenance::GROUPS
  end

  def preview
    @task = find_task
    @blocked = @task.blocked_reason
    @rows = @task.execute(commit: false) unless @blocked
  end

  def commit
    @task = find_task

    # A blank required setting or a missing reason re-renders the preview: the
    # operator fixes the problem where the form is.
    @blocked = @task.blocked_reason
    return render :preview, status: :unprocessable_entity if @blocked

    if @task.requires_reason? && params[:reason].blank?
      @reason_error = "Enter a reason -- it goes into each record's audit trail."
      @rows = @task.execute(commit: false)
      return render :preview, status: :unprocessable_entity
    end

    @rows = @task.execute(commit: true, reason: params[:reason].presence)
    render :results, status: :unprocessable_entity
  end

  private

  def find_task
    TicketingMaintenance.find(params[:task]) ||
      raise(ActiveRecord::RecordNotFound, "Unknown maintenance task #{params[:task]}")
  end
end
