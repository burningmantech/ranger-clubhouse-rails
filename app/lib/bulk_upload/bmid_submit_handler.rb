# frozen_string_literal: true

# Marks a list of people's badges for the event year as submitted -- sent off
# to be printed.
#
# Upstream's BmidHandler, whose single action id ("bmidsubmitted") is kept
# verbatim so the two applications' bulk history stays searchable together.
class BulkUpload::BmidSubmitHandler < BulkUpload::Handler
  # The only two statuses a badge may be submitted from, and upstream's pair.
  # Everything else is somebody's standing decision -- do not print, still
  # being prepped, waiting to be reprinted -- and submitting from it would
  # discard that decision without ever saying so.
  SUBMITTABLE = [Bmid::ISSUES, Bmid::READY_TO_PRINT].freeze

  # The year's badge rows, and nothing else.
  #
  # Deliberately not Bmid.find_for_person_ids, which is what upstream calls
  # here: that one runs BmidRelationshipLoader over the result -- whole person
  # rows, SAPs, sign-ups, tickets, provisions, training sign-ups, six more
  # queries -- and synthesizes an unsaved badge for everyone missing one. A
  # status is the only thing `decide` compares, and a person with no row
  # already has a known status without one being built for them.
  def preload(entries)
    @bmids = Bmid.where(year:, person_id: ids(entries)).index_by(&:person_id)
  end

  # Upstream fails an already-submitted badge alongside every other status, so
  # re-running a list that mostly went through reads as a page of errors.
  # Submitted is the state this action asks for, so it is no change here.
  def decide(entry)
    return entry.decide(:invalid, "This action takes a callsign only") unless bare?(entry)

    status = status_for(entry)
    return entry.decide(:no_change, "Already submitted for #{year}") if status == Bmid::SUBMITTED
    return entry.decide(:change) if SUBMITTABLE.include?(status)

    entry.decide(:invalid,
                 "Badge status is #{Bmid::ManageHelper::STATUS_LABELS.fetch(status, status)} and cannot be submitted")
  end

  # Taken from the preload, which fetched these rows whole -- there is no
  # projection to write back from, and re-finding each one would be a second
  # round trip for a row already in hand.
  #
  # The fallback creates a badge for a person who has none, which is upstream's
  # `?? findForPersonManage`. Nothing reaches it today -- a missing row decides
  # as in prep, and in prep is not submittable -- and it is kept so a person who
  # gains a row between the preview and the commit is still handled.
  #
  # Loading the badge bare is what makes saving it safe: Bmid#update_sap fires
  # on every save and pushes the badge's access date out to every pass the
  # person holds, but a badge no one called set_sap on carries no access pair,
  # so the callback returns before it touches one.
  def apply(entry)
    bmid = @bmids[entry.person.id] || Bmid.new(person_id: entry.person.id, year:)
    bmid.status = Bmid::SUBMITTED
    bmid.audit_reason = reason
    bmid.save!
  end

  private

  # A person with no badge row has never been anything but in prep: Bmid
  # defaults a new row to it (set_default_status), and the badge pages
  # synthesize the missing ones at that status too. The absence is an answer,
  # not a gap.
  def status_for(entry) = @bmids[entry.person.id]&.status || Bmid::IN_PREP
end
