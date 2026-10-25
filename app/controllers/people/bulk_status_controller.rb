# frozen_string_literal: true

# Changing a person's status, or marking a callsign vintage, for a list of
# callsigns at once.
#
# The Change Status group of upstream's admin/bulk-upload. Upstream offers its
# six options as one flat list; they are two different jobs and the select says
# so here. Five move the status, which grants and strips positions, roles and
# team memberships as a consequence -- the preview spells that out before
# anything is written. The sixth sets a boolean on the person's row and does
# nothing else.
#
# Not year scoped: a status and the vintage flag are the person's now, not their
# record for one event year.
class People::BulkStatusController < ApplicationController
  include BulkUploadPage

  layout "people"

  authorize_role [Role::ADMIN],
                 message: "Admin role required to change status in bulk."

  bulk_upload_page title: "Bulk Change Status",
                   icon: "users-gear",
                   description: "Set the status, or the vintage flag, for a list of callsigns.",
                   action_label: "Status or flag",
                   action_prompt: "Choose what to set",
                   records_help: "One callsign per line. Capitalisation and punctuation do not matter."

  # The ids are the status strings themselves -- StatusHandler writes the id
  # straight into person.status -- so they are named through the Person
  # constants rather than spelled out again here.
  #
  # Upstream also maps "past prospective" and "prospective waitlist" to the same
  # handler but offers neither in its UI, and they are not offered here: the
  # first is what the Past Prospective conversion does through its own page with
  # the callsign release that goes with it, and the second is a status the
  # database no longer has.
  #
  # "vintage" stays a bare string on purpose. Person::VINTAGE names the retired
  # *status* of that name, not the boolean column PersonFlagHandler writes, and
  # borrowing it here would read as a sixth status change.
  ACTIONS = [
    BulkUpload::Action.new(id: Person::ACTIVE, label: "Set as Active", group: "Status",
                           help: "callsign", handler: BulkUpload::StatusHandler),
    BulkUpload::Action.new(id: Person::ALPHA, label: "Set as Alpha", group: "Status",
                           help: "callsign", handler: BulkUpload::StatusHandler),
    BulkUpload::Action.new(id: Person::INACTIVE, label: "Set as Inactive", group: "Status",
                           help: "callsign", handler: BulkUpload::StatusHandler),
    BulkUpload::Action.new(id: Person::PROSPECTIVE, label: "Set as Prospective", group: "Status",
                           help: "callsign", handler: BulkUpload::StatusHandler),
    BulkUpload::Action.new(id: Person::RETIRED, label: "Set as Retired", group: "Status",
                           help: "callsign", handler: BulkUpload::StatusHandler),
    BulkUpload::Action.new(id: "vintage", label: "Set the Vintage Flag", group: "Flags",
                           help: "callsign", handler: BulkUpload::PersonFlagHandler)
  ].freeze

  private

  def bulk_actions = ACTIONS
end
