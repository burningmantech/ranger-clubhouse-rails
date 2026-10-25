# frozen_string_literal: true

# Recording vehicle paperwork for a list of callsigns at once.
#
# The Vehicle Paperwork Flags group of upstream's admin/bulk-upload, and the
# write side of the read-only Vehicle Paperwork audit: the audit says who is
# missing a signature, and this is how a stack of signed forms gets entered.
#
# All four flags live on the person's event-year row, so a run here changes this
# year and nothing before it.
class Vehicles::BulkPaperworkController < ApplicationController
  include BulkUploadPage

  layout "vehicles"

  authorize_role [Role::ADMIN, Role::VEHICLE_MANAGEMENT],
                 message: "Admin or Vehicle Management role required to record vehicle paperwork in bulk."

  bulk_upload_page title: "Bulk Record Vehicle Paperwork",
                   icon: "file-signature",
                   description: "Record one piece of vehicle paperwork for a list of callsigns.",
                   action_label: "Paperwork",
                   action_prompt: "Choose what to record",
                   records_help: "One callsign per line. Capitalisation and punctuation do not matter.",
                   year_scoped: true

  # Upstream's labels, kept as they read there: these name paper forms and a
  # state motor-vehicle record, and renaming them would leave the page and the
  # forms on the table disagreeing.
  ACTIONS = [
    BulkUpload::Action.new(id: "signed_motorpool_agreement",
                           label: "Signed Motorpool Agreement (gators/golf carts)",
                           help: "callsign", handler: BulkUpload::EventFlagHandler),
    BulkUpload::Action.new(id: "org_vehicle_insurance",
                           label: "Has Org Vehicle Insurance (MVR)",
                           help: "callsign", handler: BulkUpload::EventFlagHandler),
    BulkUpload::Action.new(id: "mvr_eligible",
                           label: "May Submit a MVR Request",
                           help: "callsign", handler: BulkUpload::EventFlagHandler),
    BulkUpload::Action.new(id: "may_request_stickers",
                           label: "May Request Vehicle Use Items",
                           help: "callsign", handler: BulkUpload::EventFlagHandler)
  ].freeze

  private

  def bulk_actions = ACTIONS
end
