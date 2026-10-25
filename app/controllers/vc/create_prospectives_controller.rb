# frozen_string_literal: true

# Turns approved prospective applications into Clubhouse accounts. Ported from
# the Ember vc/create-prospectives route and the Laravel
# ProspectiveApplicationController#createProspectives endpoint.
#
# Preview runs every check and reports what would happen without writing
# anything; Create Accounts does the work, one transaction per application.
# The applications come from the Clubhouse database (the Salesforce Application
# Import page put them there) -- Salesforce is only contacted to write the
# result back, and only when writebacks are enabled.
class Vc::CreateProspectivesController < ApplicationController
  layout "vc"

  authorize_role [Role::ADMIN, Role::SALESFORCE_IMPORT],
                 message: "Admin or Salesforce Import role required to create prospective accounts."

  before_action :load_settings

  # Static landing page: explainer plus the Preview / Create Accounts actions.
  def index
  end

  def preview
    run_creation(commit: false)
  end

  def commit
    run_creation(commit: true)
  end

  private

  # Both flags change what a commit actually does, so the page states them
  # before the operator presses the button.
  def load_settings
    settings = Setting.get_value([Setting::SEND_WELCOME_EMAIL, Setting::SF_ENABLE_WRITEBACKS])
    @send_welcome_email = settings[Setting::SEND_WELCOME_EMAIL]
    @sf_writebacks = settings[Setting::SF_ENABLE_WRITEBACKS]
  end

  # Results are transient -- a GET cannot re-derive them without re-running
  # every check -- so both POSTs re-render the index with the results at 422
  # (Turbo silently drops a 200 form response), matching the import page.
  def run_creation(commit:)
    @committed = commit
    batch = ProspectiveClubhouseAccountFromApplication.execute(commit:)

    if batch.auth_failure?
      @auth_error = batch.auth_error
    else
      @results = batch.results
    end

    render :index, status: :unprocessable_entity
  end
end
