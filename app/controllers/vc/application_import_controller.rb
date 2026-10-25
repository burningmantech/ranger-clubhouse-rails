# frozen_string_literal: true

# Salesforce application import: pulls the "View 1 - Check Qualifications"
# Ranger__c records and creates prospective application rows. Ported from the
# Ember vc/application-import route and the Laravel
# ProspectiveApplicationController#import endpoint.
#
# Preview is a full dress rehearsal of the pull (same queries, same mapping,
# nothing saved); Import writes each application plus its audit log entry and
# notes in one transaction per record. Both are synchronous, matching the
# preview -> commit precedent (maintenance tasks, reserved handle upload).
# Account creation is a separate, later step and is not part of this page.
class Vc::ApplicationImportController < ApplicationController
  layout "vc"

  authorize_role [Role::ADMIN, Role::SALESFORCE_IMPORT],
                 message: "Admin or Salesforce Import role required to import applications."

  # Static landing page: explainer plus the Preview / Import actions.
  # Nothing is fetched from Salesforce on entry.
  def index
  end

  def preview
    run_import(commit: false)
  end

  def commit
    run_import(commit: true)
  end

  private

  # Results are transient — a GET cannot re-derive them without re-running
  # the whole Salesforce pull — so both POSTs re-render the index with the
  # results ledger at 422 (Turbo silently drops a 200 form response). Matches
  # the maintenance tasks and the reserved handle upload.
  def run_import(commit:)
    @committed = commit
    @import = ProspectiveApplicationImport.new

    unless @import.auth
      @auth_error = @import.auth_error
      return render :index, status: :unprocessable_entity
    end

    @import.import_unprocessed(commit:)
    render :index, status: :unprocessable_entity
  end
end
