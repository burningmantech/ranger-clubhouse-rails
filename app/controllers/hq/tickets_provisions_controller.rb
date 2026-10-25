# frozen_string_literal: true

# Tickets & Provisions Progress modal for the HQ Window Interface
# (Ember port/components/hq-tickets-and-provisions*.hbs, hosted by the
# port/templates/hq.hbs modal).
#
# The shell's right-column button targets the app-wide "modal" turbo frame, so
# a plain GET here renders the dialog shell; its body is a lazy turbo frame
# that re-requests this action with ?progress=1 for the computed tables — the
# dialog opens immediately with a spinner while the progress is calculated,
# mirroring the upstream loading indicator.
class Hq::TicketsProvisionsController < ApplicationController
  include HqConcern

  # Only the person and the access gates are needed; the modal renders without
  # the shell chrome.
  skip_before_action :load_hq_shell

  def show
    if params[:progress].present?
      @progress = TicketsAndProvisionsProgress.new(@person)
      render :progress, layout: false
    else
      render layout: false
    end
  end
end
