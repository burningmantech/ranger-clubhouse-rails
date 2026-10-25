# frozen_string_literal: true

# One row of the ticketing Access Documents summary table: everything the view
# needs to describe a single person's current documents.
#
# Ported from the Ember `access-documents-for-person` component. Values only --
# the view maps each cell's `status` onto a ui_badge variant and renders the
# notes and errors. No markup, no helpers.
class AccessDocumentSummaryRow
  # The two passes a person drives in on. The LSD pass is counted separately.
  VEHICLE_PASS_TYPES = [AccessDocument::VEHICLE_PASS_SP, AccessDocument::VEHICLE_PASS_GIFT].freeze

  # Statuses worth tinting a cell for. Qualified documents render plain.
  TINTED_STATUSES = [AccessDocument::CLAIMED, AccessDocument::BANKED, AccessDocument::SUBMITTED].freeze

  # A ticket still sitting in one of these states past its expiry date is stale.
  EXPIRY_WARNING_STATUSES = [AccessDocument::BANKED, AccessDocument::QUALIFIED].freeze

  # The page holds the current documents, all for the coming event, so the year goes unsaid.
  ARRIVAL_DATE_FORMAT = DateTimeHelper::DAY_LABEL
  ARRIVAL_ANY_TIME = "Anytime"
  ARRIVAL_MISSING = "missing"
  EXPIRED_NOTE = "EXPIRED"

  # Up to three significant-other passes is normal; more than one of anything
  # else in the collection is already worth a look.
  SO_NOTE_THRESHOLD = 3
  NOTE_THRESHOLD = 1

  # A single tinted table cell. `status` is the access-document status driving
  # the tint ("claimed" / "banked" / "submitted"), or nil to render plain.
  # `value` is nil when the person has no document for that column.
  Cell = Struct.new(:value, :status, keyword_init: true) do
    # Also gives the cell a correct #blank? / #present? via ActiveSupport.
    def empty? = value.blank?
  end

  # Counts for the Special column, rendered by the view as "N Gift" / "N LSD" /
  # "N LSD VP".
  Special = Struct.new(:gift, :lsd, :lsd_vp, keyword_init: true) do
    def empty? = gift.zero? && lsd.zero? && lsd_vp.zero?
  end

  # The person holding these documents, and their documents in the order the
  # lib supplied them (by source year).
  attr_reader :person, :documents

  # Pre-formatted per-document problems ("RAD-42 - missing access date").
  attr_reader :errors

  # Cell -- short type label of the person's first Staff Credential or
  # Special Price Ticket.
  attr_reader :tickets

  # Cell -- "Anytime", "Fri 08/28/26", or ARRIVAL_MISSING.
  attr_reader :arrival

  # Date -- the day the arrival document lets this person in, or nil when
  # there is no such document, its date is missing, or it is Anytime.
  attr_reader :arrival_date

  # Cell -- short type label of the person's first Vehicle Pass.
  attr_reader :vp

  # Integer count of significant-other Setup Access Passes.
  attr_reader :so_count

  # Status tinting the SOs count, or nil. Upstream tints this column too.
  attr_reader :so_status

  # Special -- gift, LSD, and LSD vehicle pass counts.
  attr_reader :special

  # Array of "weird stuff" strings, in the order upstream collects them.
  attr_reader :notes

  def initialize(person:, documents:, errors: [])
    @person = person
    @documents = documents
    @errors = errors
    @notes = []

    # Order matters: each step appends to @notes, and upstream reads tickets,
    # then arrival, then vehicle passes, then S.O. passes.
    @tickets = build_tickets
    @arrival = build_arrival
    @vp = build_vehicle_pass
    @so_count, @so_status = build_significant_others
    @special = build_special
  end

  # Does the arrival cell say no one knows when this person gets in?
  def arrival_missing? = arrival.value == ARRIVAL_MISSING

  # The distinct statuses across the person's documents -- only those of one
  # type, when given -- one entry each, so a tally over rows counts people
  # rather than documents. The narrowing keeps a count honest under the
  # same-document rule: "Gift Ticket" while "banked" is active counts people
  # whose banked document is the Gift Ticket.
  def document_statuses(type: nil)
    documents.filter_map { |doc| doc.status if type.nil? || doc.type == type }.uniq
  end

  # The distinct types, likewise narrowable to one status.
  def document_types(status: nil)
    documents.filter_map { |doc| doc.type if status.nil? || doc.status == status }.uniq
  end

  # Does this row satisfy the summary page's filters? nil means "any".
  #
  # Status and type must hold on one document together -- "a banked Gift
  # Ticket", not a banked something beside a Gift Ticket. arrival_value is
  # an Arrival cell value -- ARRIVAL_MISSING, ARRIVAL_ANY_TIME, or a day in
  # ARRIVAL_DATE_FORMAT; issues_only asks for something in Weird Stuff.
  def matches?(status: nil, type: nil, person_status: nil, arrival_value: nil, issues_only: false)
    documents.any? { |doc| (status.nil? || doc.status == status) && (type.nil? || doc.type == type) } &&
      (person_status.nil? || person.status == person_status) &&
      (arrival_value.nil? || arrival.value == arrival_value) &&
      (!issues_only || notes.any? || errors.any?)
  end

  private

  def build_tickets
    docs = documents_of(AccessDocument::REGULAR_TICKET_TYPES)
    return Cell.new if docs.empty?

    note = count_note(docs, "tickets")

    expired = docs.select { |doc| doc.past_expire_date? && EXPIRY_WARNING_STATUSES.include?(doc.status) }
    if expired.any?
      note += "; " if note.present?
      # Name each expired document, so two of them read "SC EXPIRED SPT
      # EXPIRED" rather than a bare "EXPIRED EXPIRED". Upstream meant to do
      # this but indexed its type array by the type string and got `undefined`.
      note += expired.map { |doc| "#{doc.short_type_label} #{EXPIRED_NOTE}" }.join(" ")
    end

    @notes << note if note.present?
    cell_for(docs.first)
  end

  # First claimed Staff Credential, else any Setup Access Pass, else any Staff
  # Credential -- whichever the person will actually arrive on.
  def build_arrival
    saps = documents_of(AccessDocument::SAP)
    @notes << "#{saps.size} SAPs" if saps.size > NOTE_THRESHOLD

    doc = documents.find { |d| d.staff_credential? && d.status == AccessDocument::CLAIMED }
    doc ||= saps.first
    doc ||= documents.find(&:staff_credential?)

    # Neither a Staff Credential nor a SAP: there is no arrival for this person
    # to be missing. Most people on this page hold only a ticket, so the cell
    # reads as an empty one -- the same dash the Ticket and VP columns use --
    # instead of raising an alarm. ARRIVAL_MISSING is reserved for a document
    # that is supposed to carry an access date and does not.
    return Cell.new if doc.nil?

    # Upstream only flags the combination when the arrival document itself is a
    # Staff Credential, so it fires for a claimed SC alongside a SAP. Without a
    # claimed SC the SAP wins the lookup above and no note is added.
    @notes << "SC+SAP" if doc.staff_credential? && saps.any?

    @arrival_date = doc.access_date&.to_date unless doc.access_any_time
    Cell.new(value: arrival_value(doc), status: tint(doc))
  end

  def build_vehicle_pass
    docs = documents_of(VEHICLE_PASS_TYPES)
    return Cell.new if docs.empty?

    note = count_note(docs, "VPs")
    @notes << note if note.present?
    cell_for(docs.first)
  end

  def build_significant_others
    docs = documents_of(AccessDocument::SAPSO)
    @notes << "#{docs.size} WAPSOs" if docs.size > SO_NOTE_THRESHOLD

    [docs.size, tint(docs.first)]
  end

  def build_special
    Special.new(
      gift: documents_of(AccessDocument::GIFT).size,
      lsd: documents_of(AccessDocument::LSD).size,
      lsd_vp: documents_of(AccessDocument::VEHICLE_PASS_LSD).size
    )
  end

  def arrival_value(doc)
    return ARRIVAL_ANY_TIME if doc.access_any_time
    return ARRIVAL_MISSING if doc.access_date.blank?

    doc.access_date.strftime(ARRIVAL_DATE_FORMAT)
  end

  def documents_of(types)
    wanted = Array(types)
    documents.select { |doc| wanted.include?(doc.type) }
  end

  def cell_for(doc)
    Cell.new(value: doc.short_type_label, status: tint(doc))
  end

  def count_note(docs, label)
    (docs.size > NOTE_THRESHOLD) ? "#{docs.size} #{label}" : ""
  end

  def tint(doc)
    return nil if doc.nil?

    TINTED_STATUSES.include?(doc.status) ? doc.status : nil
  end
end
