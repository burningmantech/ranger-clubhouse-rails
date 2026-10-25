# frozen_string_literal: true

# Shift sign-ups that disagree with SAP and Staff Credential access dates.
#
# Port of the Laravel BMIDManagement::sanityCheckForYear behind the Ember
# vc/bmid-sanity-check page. Despite the name, the bmid table is never read:
# a badge record may not exist until first saved or exported, so the checks
# run on people, sign-ups, and access documents directly.
#
# Four checks, each yielding people with a prose reason:
#   1. shifts_before_access_date  -- a shift starts before the access date on
#      their best unsubmitted, usable SAP/SC.
#   2. shifts_before_submitted_wap -- the same conflict, but the document was
#      already submitted, so fixing it needs ticketing follow-up.
#   3. shifts_no_wap -- signed up for an early shift with no SAP/SC they can
#      actually use: none at all, only banked ones, or only dateless ones.
#      (Deliberate deviation from upstream, which counted a banked credential
#      as covering and filed these people under check 1 -- ruled wrong here
#      2026-07-30: a banked or dateless document gets no one through the gate.)
#   4. spt_before_box_office -- holds a Special Price Ticket plus a SAP that
#      grants access before the box office can hand them the ticket.
class BmidSanityCheckReport
  # The set of checks, their table order, and the tie-break when one person is
  # flagged by two of them. Result members, the controller's filter whitelist,
  # and the view's CHECK_META all key off this list.
  CHECK_KEYS = %i[
    shifts_before_access_date
    shifts_before_submitted_wap
    shifts_no_wap
    spt_before_box_office
  ].freeze

  # SAP/SC statuses that grant access this year. Narrower than
  # CURRENT_STATUSES: banked carries a credential to a future event and lets
  # no one in now.
  LIVE_STATUSES = AccessDocument::AVAILABLE_STATUSES

  # Statuses that never warrant a flag: not yet, or no longer, expected to
  # ranger the event on their own access.
  EXCLUDED_STATUSES = [
    Person::AUDITOR,
    Person::PROSPECTIVE,
    Person::PAST_PROSPECTIVE,
    Person::ALPHA
  ].freeze

  # The SPT check's shorter list: upstream leaves past prospective in, and the
  # asymmetry is mirrored rather than fixed.
  SPT_EXCLUDED_STATUSES = [Person::ALPHA, Person::PROSPECTIVE, Person::AUDITOR].freeze

  # The two document types that can grant pre-event access:
  # BmidManagement::EARLY_ACCESS_TYPES (SAP + Staff Credential), shared with
  # the manage roster's early-arrival category.
  ACCESS_TYPES = BmidManagement::EARLY_ACCESS_TYPES

  PERSON_COLUMNS = %i[id callsign first_name last_name status email].freeze

  # Everything the checks and reason strings read; skips the table's TEXT
  # columns (comments, name), which are dead weight at pool sizes.
  DOCUMENT_COLUMNS = %i[id person_id type status access_date access_any_time].freeze

  Row = Data.define(:person, :reason)

  # A person's earliest qualifying shift sign-up.
  Shift = Data.define(:begins, :position_title) do
    # Same getlocal dance as SapCandidatesReport::SignUp#begins_label -- see
    # the timezone note there.
    def begins_label
      begins.getlocal.strftime(DateTimeHelper::MONTH_DAY_TIME)
    end
  end

  # One row of the merged findings table.
  Finding = Data.define(:check, :person, :reason)

  Result = Data.define(*CHECK_KEYS, :box_office_open) do
    # The merged table, callsign-first so a person flagged by two checks sits
    # on adjacent rows. Pass a check key (symbol or string) to narrow.
    def findings(check: nil)
      keys = check ? [check.to_sym] : CHECK_KEYS
      keys.flat_map { |key|
        public_send(key).map { |row| Finding.new(check: key, person: row.person, reason: row.reason) }
      }.sort_by { |finding| [finding.person.callsign.downcase, CHECK_KEYS.index(finding.check)] }
    end

    # @return [Hash{Symbol => Integer}] finding count per check, for the tiles
    def counts
      CHECK_KEYS.index_with { |key| public_send(key).size }
    end

    def total
      counts.values.sum
    end
  end

  # @param year [Integer]
  # @return [Result]
  def self.execute(year)
    new(year).execute
  end

  def initialize(year)
    @year = year
  end

  def execute
    before, submitted = shifts_before_access_checks

    # Raw setting string or nil. Upstream throws on a blank setting and the
    # whole page 500s; here the check just sits out and the view says why.
    box_office_open = Setting.get_value(Setting::TAS_BOX_OFFICE_OPEN_DATE).presence

    Result.new(shifts_before_access_date: before,
               shifts_before_submitted_wap: submitted,
               shifts_no_wap: early_shifts_without_sap,
               spt_before_box_office: spt_before_box_office(box_office_open),
               box_office_open:)
  end

  private

  def event_cutoff
    @event_cutoff ||= UnclaimedTicketsWithSignupsReport.signup_cutoff(@year)
  end

  # The earliest shift start that counts as "early" for the no-SAP check:
  # August 10th, five days before the event-start cutoff the other checks use.
  # Time.local, not Time.zone: slot.begins is stored in system-local time, so
  # a zoned boundary lands an hour off.
  def early_shift_cutoff
    Time.local(@year, 8, 10)
  end

  # Checks 1 and 2 in one pass: pool everyone signed up for a real (active,
  # non-training) shift after gate opens, then compare each person's earliest
  # such shift against their best usable SAP/SC. People without a usable
  # document are check 3's business, not a date conflict.
  #
  # @return [Array(Array<Row>, Array<Row>)] [before_access, before_submitted]
  def shifts_before_access_checks
    before = []
    submitted = []

    slots = Slot.for_year(@year)
                .active
                .where("begins > ?", event_cutoff)
                .where.not(position_id: BmidManagement::TRAINING_POSITIONS)
    people = flaggable_people(signed_up_ids(slots))
    return [before, submitted] if people.empty?

    docs = live_documents_by_person(people.map(&:id))
    shifts = earliest_event_shift_by_person(people.map(&:id))

    people.each do |person|
      qualified = pick_qualified_document(docs[person.id])

      # No usable document is check 3's finding; any-time access clears.
      next if qualified.nil? || qualified.access_any_time

      earliest = shifts[person.id]
      next unless earliest && earliest.begins < qualified.access_date

      row = Row.new(person:, reason: before_access_reason(earliest, qualified))
      (qualified.status == AccessDocument::SUBMITTED ? submitted : before) << row
    end

    [before, submitted]
  end

  # Check 3: signed up for any early shift with no SAP/SC they can actually
  # use. Usable means live (claimed/submitted/qualified) AND carrying an
  # access date or any-time access -- a banked credential is parked at a
  # future event and a dateless one grants nothing, so both land here.
  # The slot pool still mirrors upstream: inactive and training slots count,
  # and the cutoff is Aug 10.
  def early_shifts_without_sap
    slots = Slot.for_year(@year).where("begins > ?", early_shift_cutoff)
    signed_up = signed_up_ids(slots)
    return [] if signed_up.empty?

    # Two plucks and a set difference rather than NOT EXISTS.
    covered = AccessDocument.where(person_id: signed_up,
                                   type: ACCESS_TYPES,
                                   status: LIVE_STATUSES)
                            .where("access_date IS NOT NULL OR access_any_time = TRUE")
                            .distinct
                            .pluck(:person_id)
    people = flaggable_people(signed_up - covered)
    return [] if people.empty?

    ids = people.map(&:id)
    shifts = earliest_shift_by_person(
      PersonSlot.joins(slot: :position).where(person_id: ids, slot_id: slots.select(:id))
    )
    banked = banked_credentials_by_person(ids)
    # Every live document a flagged person still holds is dateless by
    # definition -- a dated or any-time one would have covered them above.
    dateless = live_documents_by_person(ids)

    people.map do |person|
      Row.new(person:, reason: missing_sap_reason(shifts[person.id],
                                                  banked[person.id],
                                                  dateless[person.id] || []))
    end
  end

  # Check 4: a Special Price Ticket holder whose SAP lets them in before the
  # box office can hand them the ticket they will arrive expecting.
  def spt_before_box_office(box_office_open)
    return [] if box_office_open.nil?

    # access_date < ? is NULL-filtering, so a pure any-time SAP (no date set)
    # never lands here even though it grants the earliest access of all.
    # Upstream behaves identically; the quirk is kept, not silently fixed.
    spt_holders = AccessDocument.where(type: AccessDocument::SPT, status: LIVE_STATUSES)
                                .select(:person_id)
    saps_by_person = AccessDocument.where(type: AccessDocument::SAP, status: LIVE_STATUSES)
                                   .where(person_id: spt_holders)
                                   .where("access_date < ?", box_office_open)
                                   .order(:person_id, :id)
                                   .group_by(&:person_id)
    return [] if saps_by_person.empty?

    flaggable_people(saps_by_person.keys, excluded: SPT_EXCLUDED_STATUSES)
      .map { |person| Row.new(person:, reason: spt_sap_reason(saps_by_person[person.id].first)) }
  end

  # The distinct people signed up on the given slots. Takes the slot relation
  # and lets the database resolve it as a subquery rather than shipping a
  # plucked id list back and forth.
  def signed_up_ids(slots)
    PersonSlot.where(slot_id: slots.select(:id)).distinct.pluck(:person_id)
  end

  # The ones a check may flag, in page order. order(:callsign) is already
  # case-insensitive -- person rows collate utf8mb4_unicode_ci and callsign
  # carries a unique index -- so the ordering costs nothing.
  def flaggable_people(person_ids, excluded: EXCLUDED_STATUSES)
    return [] if person_ids.empty?

    Person.where(id: person_ids)
          .where.not(status: excluded)
          .select(*PERSON_COLUMNS)
          .order(:callsign)
          .to_a
  end

  def live_documents_by_person(person_ids)
    AccessDocument.where(type: ACCESS_TYPES, status: LIVE_STATUSES, person_id: person_ids)
                  .select(*DOCUMENT_COLUMNS)
                  .group_by(&:person_id)
  end

  # Banked staff credentials let no one in, but the missing-SAP reason mentions
  # them: the fix is often to unbank one.
  def banked_credentials_by_person(person_ids)
    AccessDocument.where(type: AccessDocument::STAFF_CREDENTIAL,
                         status: AccessDocument::BANKED,
                         person_id: person_ids)
                  .select(*DOCUMENT_COLUMNS)
                  .group_by(&:person_id)
  end

  # Every non-training shift from the event cutoff on. Bounded to the report
  # year where upstream scanned all future years -- the difference only shows
  # for access dates past December, which is garbage data -- and deliberately
  # not bounded to active slots, which upstream also scans: the pool decides
  # who gets checked, this only decides which shift the reason names.
  def earliest_event_shift_by_person(person_ids)
    earliest_shift_by_person(
      PersonSlot.joins(slot: :position)
                .where(person_id: person_ids)
                .where(slot: { begins_year: @year, begins: event_cutoff.. })
                .where.not(slot: { position_id: BmidManagement::TRAINING_POSITIONS })
    )
  end

  # Only the earliest shift per person is ever read: the list ascends, so if
  # the earliest starts after the access date every later one does too
  # (upstream scans the same order and stops at the first hit).
  #
  # @return [Hash{Integer => Shift}]
  def earliest_shift_by_person(person_slots)
    person_slots.order("slot.begins")
                .pluck(:person_id, "slot.begins", "position.title")
                .each_with_object({}) do |(person_id, begins, title), acc|
                  acc[person_id] ||= Shift.new(begins:, position_title: title)
                end
  end

  # Port of upstream pickQualifiedAccessDocument: any-time access wins, then
  # the earliest access date; documents with neither are unusable and skipped
  # (check 3 surfaces them in its reason text). AccessDocument.sap_candidate
  # is deliberately not this method -- it keeps dateless documents via a
  # far-future fallback.
  #
  # @return [AccessDocument, nil]
  def pick_qualified_document(docs)
    qualified = nil

    (docs || []).each do |doc|
      next if doc.access_date.nil? && !doc.access_any_time

      # The access_date guard mirrors upstream: an any-time incumbent with no
      # date must not be displaced by an earlier-dated document.
      if qualified.nil? || doc.access_any_time ||
         (qualified.access_date && doc.access_date && doc.access_date < qualified.access_date)
        qualified = doc
      end
    end

    qualified
  end

  def before_access_reason(shift, doc)
    "Shift #{shift.position_title} #{shift.begins_label} is before #{doc.display_ref} " \
      "#{doc.type_label} access date #{doc.access_date.to_date.iso8601} status #{doc.status}"
  end

  def missing_sap_reason(first_shift, banked_docs, dateless_docs)
    parts = ["No usable SAP or Staff Credential."]
    parts << "First shift #{first_shift.position_title} #{first_shift.begins_label}." if first_shift
    (banked_docs || []).each { |doc| parts << "#{doc.display_ref} Staff Credential banked." }
    dateless_docs.each { |doc| parts << "#{doc.display_ref} #{doc.type_label} status #{doc.status} has no access date." }
    parts.join(" ")
  end

  # Upstream's third branch -- a dated document with no date -- is unreachable
  # behind the access_date filter above and is dropped.
  def spt_sap_reason(doc)
    if doc.access_any_time
      "#{doc.display_ref} #{doc.type_label} status #{doc.status} access any time"
    else
      "#{doc.display_ref} #{doc.type_label} status #{doc.status} access date #{doc.access_date.to_date.iso8601}"
    end
  end
end
