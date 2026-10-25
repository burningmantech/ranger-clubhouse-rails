# frozen_string_literal: true

# Records one signed agreement for each callsign on the list.
#
# Upstream folds this into its EventColumnHandler and sets the person_event
# column directly, and so did this page at first. The write goes through
# Agreements.admin_set_signature instead: that is the application's single path
# for an administratively recorded signature, and it is what writes the
# `agreement-signature` action log row the admin Action Logs page offers as a
# filter. Setting the column by hand left a bulk-recorded affidavit with no
# per-person history anywhere -- person_event keeps none of its own -- so two
# hundred signatures recorded here were invisible to the one report that answers
# "when was this signed, and who recorded it".
class BulkUpload::AgreementSignatureHandler < BulkUpload::Handler
  # Action id to document tag. The id stays the person_event column name, which
  # is upstream's spelling and what the bulk history is searched by; the tag is
  # what the agreements API keys on.
  TAGS = { "sandman_affidavit" => Document::SANDMAN_AFFIDAVIT_TAG }.freeze

  def initialize(...)
    super
    @tag = TAGS[action.id]
    @paper = @tag && Agreements::DOCUMENTS[@tag]
    return if @paper

    raise ArgumentError, "#{self.class} cannot record agreement [#{action.id}]"
  end

  # One query for the year's rows -- and the same rows are handed back to
  # Agreements on apply, so the write does not fetch them a second time.
  def preload(entries)
    @events = PersonEvent.find_all_for_ids_year(ids(entries), year).index_by(&:person_id)
  end

  def decide(entry)
    return entry.decide(:invalid, "This action takes a callsign only") unless bare?(entry)
    return entry.decide(:no_change, "Already recorded for #{year}") if signed?(entry)

    entry.decide(:change)
  end

  # entry.person's four-column projection is enough: for an annual agreement
  # admin_set_signature reads nothing off the person but its id.
  def apply(entry)
    Agreements.admin_set_signature(entry.person, @tag, true, person_event: @events[entry.person.id])
  end

  private

  def signed?(entry) = @events[entry.person.id]&.public_send(@paper[:column]) == true
end
