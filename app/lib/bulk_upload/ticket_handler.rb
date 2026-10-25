# frozen_string_literal: true

# Creating one access document -- a ticket, a pass, or a credential -- for each
# callsign on the list.
#
# Upstream's TicketHandler, with the TicketTypeCode enum it dispatches on folded
# in as three lists: an enum of nine cases whose whole content is "which type,
# which optional columns" reads better in Ruby as the table it always was.
#
# The line is `callsign,type` plus up to three optional columns, and the columns
# are positional: which ones a line may carry depends entirely on its type, so
# `hubcap,SPT,2024` is a source year while `hubcap,CRED,2024-08-10` is an access
# date. That is upstream's format and the lists being pasted are written to it.
class BulkUpload::TicketHandler < BulkUpload::Handler
  # The codes the second column accepts and the document each one creates.
  #
  # WAP and SAP produce the same document: the pass was renamed and
  # AccessDocument::SAP still carries the legacy "work_access_pass" value, so
  # both spellings are accepted -- the lists pasted here were written over
  # several years and half of them say WAP.
  TYPES = {
    "CRED" => AccessDocument::STAFF_CREDENTIAL,
    "SPT" => AccessDocument::SPT,
    "LSD" => AccessDocument::LSD,
    "GIFT" => AccessDocument::GIFT,
    "VP" => AccessDocument::VEHICLE_PASS_SP,
    "VPGIFT" => AccessDocument::VEHICLE_PASS_GIFT,
    "VPLSD" => AccessDocument::VEHICLE_PASS_LSD,
    "WAP" => AccessDocument::SAP,
    "SAP" => AccessDocument::SAP
  }.freeze

  # Only these three carry an access date, and only these two an expiry year;
  # anything else in those positions is refused rather than ignored.
  ACCESS_DATE_CODES = %w[CRED WAP SAP].freeze
  EXPIRY_YEAR_CODES = %w[SPT CRED].freeze

  # These are always this year's, whatever the season says the default is: a
  # gift, an LSD ticket or a SAP is allocated for the event about to happen and
  # never carries forward. An explicit source-year column still wins, which is
  # upstream's behaviour -- the override is a default, not a lock.
  CURRENT_YEAR_CODES = %w[LSD GIFT VPGIFT VPLSD WAP SAP].freeze

  # A line that parsed: everything the document is created from, and nothing
  # about the person, so `decide` and `apply` can each derive it from the same
  # text and cannot disagree about what the line asked for.
  Ticket = Struct.new(:type, :source_year, :expiry_year, :access_date, keyword_init: true)

  # The line format as a table: every code, the document it creates, and the
  # optional columns it accepts. Built from the same three lists `parse`
  # enforces, so the help the page prints cannot drift from the rules it is
  # describing. WAP and SAP are listed as the two rows they are typed as.
  #
  # @return [Array<Array>] code, document label, and the extra columns allowed
  def self.line_formats
    TYPES.map do |code, type|
      extras = []
      extras << "access date" if ACCESS_DATE_CODES.include?(code)
      extras << "source year" if AccessDocument::TICKET_TYPES.include?(type)
      extras << "expiry year" if EXPIRY_YEAR_CODES.include?(code)

      [code, AccessDocument::TYPE_LABELS.fetch(type), extras]
    end
  end

  # Two bulk queries, one per question the preview asks.
  #
  # Upstream's is one query with no person filter at all -- it loads every SAP
  # and credential in the database to answer a question about the handful of
  # people on the list, and pays for it twice because the preview and the commit
  # each run the whole handler. Scoped to the listed people here.
  def preload(entries)
    person_ids = ids(entries)
    # Which document a new SAP would have to live alongside. The same "which one
    # counts" rule the SAP date action uses, so the two actions cannot name
    # different documents for the same person.
    @saps = AccessDocument.find_sap_for_person_ids(person_ids)
    # Four columns, because all the preview does with these is say "you already
    # hold RAD-42". The full row carries a mailing address and the document's
    # whole comment history, and a 300-callsign paste holding half a dozen
    # documents each would haul all of it to answer a yes/no question.
    @existing = AccessDocument.valid
                              .where(person_id: person_ids)
                              .select(:id, :person_id, :type, :status)
                              .group_by(&:person_id)
  end

  def decide(entry)
    ticket, problem = parse(entry)
    return entry.decide(:invalid, problem) if problem

    problem = shortened_access(entry, ticket)
    return entry.decide(:invalid, problem) if problem

    held = held_of_type(entry, ticket)
    return entry.decide(:change, summary(ticket)) if held.empty?

    # Nothing is overwritten -- a second document is created alongside the first
    # -- but this is the row a reader has to stop on, and amber is the only
    # badge that stops them. The message says what actually happens.
    entry.decide(:replace,
                 "#{summary(ticket)}. Already holds #{held.map(&:display_ref).to_sentence} " \
                 "of this type — this adds another.")
  end

  # Re-parsed rather than carried over from `decide`: the batch re-decides every
  # line against freshly preloaded state before it applies any of them, so the
  # same text is read twice by the same code instead of once into a cache that
  # could outlive the row it described.
  def apply(entry)
    ticket, = parse(entry)

    # expiry_date takes the bare year: the model's setter expands it to the
    # mid-September date the column holds.
    #
    # delivery_method is passed for every type because the column is NOT NULL
    # with no database default and set_delivery_method_by_type does not cover
    # them all -- its SPT arm is guarded by status_changed?, which is false on a
    # new record whose status equals the column default, and vehicle passes and
    # LSD tickets have no arm at all. The callback still wins where it has an
    # opinion: email for a SAP, will call for a credential.
    #
    # additional_comments is the model's own stamp, "<time> <callsign>: <text>"
    # -- upstream's comment shape from upstream's format string, so the two
    # applications' comment logs read as one.
    # audit_reason as well as the comment: AccessDocument is an audit model, and
    # without it every row this page creates gets an audit entry with an empty
    # message -- the reason would live only in the free-text comment column,
    # where the audit log cannot be searched by it.
    document = AccessDocument.new(person_id: entry.person.id,
                                  type: ticket.type,
                                  source_year: ticket.source_year,
                                  expiry_date: ticket.expiry_year,
                                  access_date: ticket.access_date,
                                  status: AccessDocument::QUALIFIED,
                                  delivery_method: AccessDocument::DELIVERY_NONE,
                                  additional_comments: reason)
    document.audit_reason = reason
    document.save!
  end

  private

  # The line, read left to right. Returns [ticket, nil] or [nil, refusal].
  #
  # The order of the checks is upstream's and is load bearing: a line with both
  # a stray column and an unparseable date reports the stray column, because
  # that is the mistake that explains the other one.
  def parse(entry)
    values = columns(entry)
    return [nil, "missing ticket type"] if values.empty?

    input = values.shift
    code = input.upcase
    type = TYPES[code]
    return [nil, "Unknown ticket type [#{input}]"] unless type

    source_default, expiry_default = self.class.default_years
    source_year = CURRENT_YEAR_CODES.include?(code) ? year : source_default
    expiry_year = EXPIRY_YEAR_CODES.include?(code) ? expiry_default : year

    # Read now, checked last, so the column count is judged before the contents.
    access_input = values.shift if ACCESS_DATE_CODES.include?(code) && values.any?

    # Keyed off the type rather than the code: a source year is a ticket's
    # property, and the passes and SAPs that are not tickets do not take one.
    if AccessDocument::TICKET_TYPES.include?(type) && values.any?
      source_year, problem = check_year_range(values.shift, source: true)
      return [nil, problem] if problem
    end

    if EXPIRY_YEAR_CODES.include?(code) && values.any?
      expiry_year, problem = check_year_range(values.shift, source: false)
      return [nil, problem] if problem
    end

    label = AccessDocument::TYPE_LABELS.fetch(type)
    return [nil, "Unexpected additional data for #{label}. See the required line format"] if values.any?

    if expiry_year < source_year
      return [nil, "Source year [#{source_year}] must not be after expiry year [#{expiry_year}]"]
    end

    access_date = nil
    if access_input
      access_date, problem = parse_access_date(access_input)
      return [nil, problem] if problem
    end

    [Ticket.new(type:, source_year:, expiry_year:, access_date:), nil]
  end

  # Upstream's parseAccessDate. Returns [time, nil] or [nil, refusal].
  #
  # The length guard is the whole point of it: a date cannot be written in four
  # characters, but "2026" parses happily as 20:26 today, so a source year typed
  # into the access-date column would become a valid date rather than a refusal.
  def parse_access_date(input)
    invalid = "Access date is invalid. Try YYYY-MM-DD format. [#{input}]"
    return [nil, invalid] if input.length <= 4

    parsed = begin
      Time.zone.parse(input)
    rescue ArgumentError
      nil
    end

    return [nil, invalid] if parsed.nil?
    return [nil, "Access date is before this year #{year} [#{input}]"] if parsed.year < year

    [parsed, nil]
  end

  # Upstream's wapDoesNotShortenAccess: a new SAP must not be the reason someone
  # arrives later than the credential they already hold.
  #
  # Upstream reaches for $sap->access_date->lt() without checking it is set,
  # which raises on the any-time SAP its own candidate rule prefers. Guarded
  # here; that document is still flagged, as the amber "already holds one" row.
  #
  # @return [String, nil] the refusal, or nil when the line is fine
  def shortened_access(entry, ticket)
    return nil unless ticket.type == AccessDocument::SAP

    sap = @saps[entry.person.id]
    return nil unless sap

    if sap.staff_credential? && sap.access_any_time
      return "#{document_label(sap)} already gives access at any time. A SAP would take that away."
    end

    return nil if ticket.access_date.nil? || sap.access_date.nil?
    return nil unless sap.access_date < ticket.access_date

    "#{document_label(sap)} already gives access on #{format_date(sap.access_date)}, earlier than " \
      "#{format_date(ticket.access_date)}. This SAP would push access back."
  end

  def held_of_type(entry, ticket)
    documents = @existing[entry.person.id] || []
    documents.select { |document| document.type == ticket.type }
  end

  # What the line will create, spelled out. The source and expiry years are the
  # two things a reader cannot check by reading their own list back, because
  # most lines never mention them.
  def summary(ticket)
    parts = ["#{AccessDocument::TYPE_LABELS.fetch(ticket.type)}, source year #{ticket.source_year}",
             "expires #{ticket.expiry_year}"]
    parts << "access from #{format_date(ticket.access_date)}" if ticket.access_date
    parts.join(", ")
  end

  def document_label(document) = "#{document.type_label} #{document.display_ref} (#{document.status})"
end
