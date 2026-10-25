# frozen_string_literal: true

# Sets one boolean on the person's own row: today only the vintage flag.
#
# Upstream's PersonColumnHandler, whitelist and all. The whitelist is kept for
# the reason upstream states and EventFlagHandler repeats: a page only ever hands
# over an id from its own frozen list, so this is the difference between a
# mistyped action id raising at boot and it writing an arbitrary person column.
#
# One-way, like upstream: there is a flag to set and no flag to clear. Taking
# vintage back off a callsign is a per-person edit under Person Management, and
# is deliberately not a thing a pasted list can do to two hundred people.
class BulkUpload::PersonFlagHandler < BulkUpload::Handler
  COLUMNS = %w[vintage].freeze

  def initialize(...)
    super
    return if COLUMNS.include?(action.id)

    raise ArgumentError, "#{self.class} cannot set person column [#{action.id}]"
  end

  # One query for the column, because it is not one of the four the batch's
  # narrow person projection carries -- reading entry.person.vintage would raise
  # ActiveRecord::MissingAttributeError.
  def preload(entries)
    @flags = Person.where(id: ids(entries)).pluck(:id, action.id.to_sym).to_h
  end

  def decide(entry)
    return entry.decide(:invalid, "This action takes a callsign only") unless bare?(entry)
    return entry.decide(:no_change, "Already marked #{action.id}") if @flags[entry.person.id]

    entry.decide(:change)
  end

  # Re-found whole because entry.person is the batch's four-column projection.
  # Validation is skipped for upstream's reason (saveWithoutValidation): a record
  # with an unrelated validation problem must still be able to have its callsign
  # marked, and the mark says nothing about the rest of the record.
  def apply(entry)
    person = Person.find(entry.person.id)
    person[action.id] = true
    person.audit_reason = reason
    person.save!(validate: false)
  end
end
