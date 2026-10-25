# frozen_string_literal: true

# Marking a list of badges as submitted at once.
#
# The BMID Actions group of upstream's admin/bulk-upload. One action today --
# submitted -- and it is still offered through a select rather than assumed,
# because the next badge action to be done in bulk arrives as a line in the
# list below and nothing else about the page has to change.
class Ticketing::BulkBmidController < ApplicationController
  include BulkUploadPage

  # The BMID sidebar, not Ticketing's. The URL keeps this page with its bulk
  # siblings under /ticketing, but the only menu offering it is BMID, whose
  # gate is the pair below -- Edit BMIDs is not a ticketing role, so a reader
  # arriving from Manage Badges would lose the menu they came from.
  layout "bmid"

  authorize_role [Role::ADMIN, Role::EDIT_BMIDS],
                 message: "Admin or Edit BMIDs role required to change badges in bulk."

  bulk_upload_page title: "Bulk Badge Actions",
                   icon: "id-card",
                   description: "Mark the badges of a list of callsigns as submitted, in one pass.",
                   action_label: "Badge action",
                   action_prompt: "Choose a badge action",
                   records_help: "One callsign per line. Capitalisation and punctuation do not matter.",
                   year_scoped: true

  ACTIONS = [
    BulkUpload::Action.new(id: "bmidsubmitted",
                           label: "Mark BMID as submitted",
                           help: "callsign",
                           handler: BulkUpload::BmidSubmitHandler)
  ].freeze

  private

  def bulk_actions = ACTIONS
end
