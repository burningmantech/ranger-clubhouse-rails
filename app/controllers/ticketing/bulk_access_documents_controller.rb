# frozen_string_literal: true

# Creating tickets, passes and credentials for a pasted list of callsigns, and
# correcting the day a list of people may arrive on.
#
# The Ticket Actions group of upstream's admin/bulk-upload. Two actions that
# have almost nothing in common -- one creates documents, the other only ever
# updates ones that already exist -- but they are the two things a ticketing
# admin does to an access document in bulk, and splitting them across two pages
# would put the same list in front of the same person twice.
#
# The second action keeps upstream's id, "wap". The pass was renamed to SAP and
# every word on this page says SAP, but the id is what the action_log rows are
# searched by and both applications write into the same table.
class Ticketing::BulkAccessDocumentsController < ApplicationController
  include BulkUploadPage

  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to create access documents in bulk."

  bulk_upload_page title: "Bulk Access Documents",
                   icon: "ticket",
                   description: "Create tickets, passes and credentials for a list of callsigns, " \
                                "or set the day those people may arrive.",
                   records_label: "Records",
                   records_help: "One record per line, in the format for the action you chose."
  # Deliberately not year_scoped. The shared year callout promises that nothing
  # outside the event year is touched, and a document created here carries a
  # source year and an expiry year that routinely straddle several: a Special
  # Price Ticket bought last season expires four years out. The years each line
  # actually lands on are named in the line-format panel and again on every row
  # of the preview, which is where they can be checked against the list.

  ACTIONS = [
    BulkUpload::Action.new(id: "tickets",
                           label: "Create Access Documents",
                           help: "callsign,type[,access date][,source year][,expiry year]",
                           handler: BulkUpload::TicketHandler),
    BulkUpload::Action.new(id: "wap",
                           label: "Update SAP dates",
                           help: "callsign,date",
                           handler: BulkUpload::SapDateHandler)
  ].freeze

  private

  def bulk_actions = ACTIONS
end
