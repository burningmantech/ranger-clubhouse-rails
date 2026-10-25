# frozen_string_literal: true

# Granting provisions -- meal passes, showers and event radios -- to a pasted
# list of callsigns.
#
# The two provision groups of upstream's admin/bulk-upload, still two groups in
# one select. Earned and allocated are not two flavours of the same grant: an
# earned provision is credited to the season it was rangered in and lasts
# several years, an allocated one is handed out for this year only. That split
# is why the select is grouped and why the two halves take different lines.
class Ticketing::BulkProvisionsController < ApplicationController
  include BulkUploadPage

  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to grant provisions in bulk."

  bulk_upload_page title: "Bulk Grant Provisions",
                   icon: "gear",
                   description: "Grant one provision to a list of callsigns.",
                   action_label: "Provision",
                   action_prompt: "Choose a provision",
                   records_label: "Callsigns",
                   records_help: "One callsign per line. Capitalisation and punctuation do not matter. " \
                                 "What else a line may carry depends on the provision — the formats are below."
  # Deliberately not year_scoped. The shared year callout promises that nothing
  # outside the event year is touched, which is true of an allocated provision
  # and false of an earned one: granted in April, an earned pass is credited to
  # last season and expires four years on. The years are named in the
  # line-format panel and on every row of the preview instead, where they can be
  # checked against the list rather than asserted over the top of it.

  EARNED = "Earned Provisions"
  ALLOCATED = "Allocated Provisions"

  HELP_YEARS = "callsign[,source year,expiry year]"
  HELP_RADIO_YEARS = "callsign,count[,source year,expiry year]"
  HELP_CALLSIGN = "callsign"
  HELP_RADIO = "callsign,radio count"

  # Upstream's ids and upstream's order. The ids are the value the select posts
  # and the string every history row is written under, so "alloc_" prefixes and
  # the doubled "event" in event_post_event_eat_pass are kept exactly as spelled.
  #
  # Only two of the seven meal passes can be earned. That is upstream's list,
  # not an omission: the other five are only ever handed out.
  ACTIONS = [
    BulkUpload::Action.new(id: "all_eat_pass", label: "Earned All Eat Pass", group: EARNED,
                           help: HELP_YEARS, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: "event_eat_pass", label: "Earned Event Eat Pass", group: EARNED,
                           help: HELP_YEARS, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: Provision::WET_SPOT, label: "Earned Wet Spot", group: EARNED,
                           help: HELP_YEARS, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: Provision::EVENT_RADIO, label: "Earned Event Radio", group: EARNED,
                           help: HELP_RADIO_YEARS, handler: BulkUpload::ProvisionHandler),

    BulkUpload::Action.new(id: "alloc_all_eat_pass", label: "Allocated All Eat Pass", group: ALLOCATED,
                           help: HELP_CALLSIGN, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: "alloc_event_eat_pass", label: "Allocated Event Eat Pass", group: ALLOCATED,
                           help: HELP_CALLSIGN, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: "alloc_pre_event_eat_pass", label: "Allocated Pre-Event Eat Pass", group: ALLOCATED,
                           help: HELP_CALLSIGN, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: "alloc_pre_event_event_eat_pass", label: "Allocated Pre-Event + Event Eat Pass",
                           group: ALLOCATED, help: HELP_CALLSIGN, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: "alloc_pre_post_eat_pass", label: "Allocated Pre+Post Eat Pass", group: ALLOCATED,
                           help: HELP_CALLSIGN, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: "alloc_event_post_event_eat_pass", label: "Allocated Event + Post Eat Pass",
                           group: ALLOCATED, help: HELP_CALLSIGN, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: "alloc_post_event_eat_pass", label: "Allocated Post-Event Eat Pass", group: ALLOCATED,
                           help: HELP_CALLSIGN, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: "alloc_#{Provision::WET_SPOT}", label: "Allocated Wet Spot", group: ALLOCATED,
                           help: HELP_CALLSIGN, handler: BulkUpload::ProvisionHandler),
    BulkUpload::Action.new(id: "alloc_#{Provision::EVENT_RADIO}", label: "Allocated Event Radio", group: ALLOCATED,
                           help: HELP_RADIO, handler: BulkUpload::ProvisionHandler)
  ].freeze

  private

  def bulk_actions = ACTIONS
end
