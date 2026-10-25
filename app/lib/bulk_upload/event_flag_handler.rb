# frozen_string_literal: true

# Sets one of the vehicle paperwork booleans on a person's record for the event
# year.
#
# Upstream's EventColumnHandler, which serves five ids from the one page. Four
# of them are here; the fifth, the Sandman affidavit, is a signature rather than
# a flag and goes through BulkUpload::AgreementSignatureHandler so that the
# application's agreement history records it.
#
# The column whitelist is kept even though a page only ever hands over an id
# from its own frozen list: it is the difference between a mistyped action id
# raising at boot and it writing an arbitrary column.
class BulkUpload::EventFlagHandler < BulkUpload::Handler
  COLUMNS = %w[org_vehicle_insurance signed_motorpool_agreement may_request_stickers
               mvr_eligible].freeze

  def initialize(...)
    super
    return if COLUMNS.include?(action.id)

    raise ArgumentError, "#{self.class} cannot set person_event column [#{action.id}]"
  end

  # One query for the year's rows. A person with no row yet simply has none --
  # the flag is false by default, and apply creates the row.
  def preload(entries)
    @events = PersonEvent.find_all_for_ids_year(ids(entries), year).index_by(&:person_id)
  end

  def decide(entry)
    return entry.decide(:invalid, "This action takes a callsign only") unless bare?(entry)
    return entry.decide(:no_change, "Already recorded for #{year}") if already_set?(entry)

    entry.decide(:change)
  end

  # A person with no row for the year gets one here, which is upstream's
  # behaviour and the only way a flag can be recorded before anything else has
  # touched their event year.
  #
  # Built from the preloaded row rather than re-found: `preload` already fetched
  # every one of these whole (no projection), so a per-line find_or_initialize_by
  # would be a second round trip for a row already in hand.
  def apply(entry)
    event = @events[entry.person.id] || PersonEvent.new(person_id: entry.person.id, year:)
    event[action.id] = true
    event.audit_reason = reason
    event.save!
  end

  private

  def already_set?(entry) = @events[entry.person.id]&.public_send(action.id) == true
end
