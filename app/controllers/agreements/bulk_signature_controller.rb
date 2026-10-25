# frozen_string_literal: true

# Recording a signed agreement for a list of callsigns at once.
#
# The Affidavits group of upstream's admin/bulk-upload. One agreement today --
# the Sandman affidavit -- and it is still offered through a select rather than
# assumed, because the next one to be recorded in bulk arrives as a line in the
# list below and nothing else about the page has to change.
class Agreements::BulkSignatureController < ApplicationController
  include BulkUploadPage

  layout "agreements"

  authorize_role [Role::ADMIN],
                 message: "Admin role required to record signed agreements in bulk."

  bulk_upload_page title: "Bulk Record a Signed Agreement",
                   icon: "file-signature",
                   description: "Record one signed agreement for a list of callsigns.",
                   action_label: "Agreement",
                   action_prompt: "Choose an agreement",
                   records_help: "One callsign per line. Capitalisation and punctuation do not matter.",
                   year_scoped: true

  ACTIONS = [
    BulkUpload::Action.new(id: "sandman_affidavit",
                           label: "Signed Sandman Affidavit",
                           help: "callsign",
                           handler: BulkUpload::AgreementSignatureHandler)
  ].freeze

  private

  def bulk_actions = ACTIONS
end
