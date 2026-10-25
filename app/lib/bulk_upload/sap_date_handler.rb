# frozen_string_literal: true

# Setting the day a list of people may arrive on, on the Setup Access Passes and
# Staff Credentials they already hold.
#
# Upstream's SapHandler. It creates nothing: a callsign with no SAP and no
# credential is refused rather than given one, because the pass is earned and
# this page is where a date is corrected, not where access is granted.
#
# The write is deliberately wider than the check. AccessDocument's own
# update_saps_for_person sets the date on every qualified, claimed or banked SAP
# and Staff Credential the person holds, while the preview can only examine the
# one document the candidate rule picks out -- so the page says so out loud in
# its consequence note rather than implying one row changes.
class BulkUpload::SapDateHandler < BulkUpload::Handler
  # Anytime access, spelled as the admin forms spell it.
  ANY = AccessDocument::ADMISSION_ANY

  # The statuses AccessDocument.update_saps_for_person writes to. Named here
  # because the guard below has to cover exactly what the write reaches.
  WRITTEN_STATUSES = [AccessDocument::QUALIFIED, AccessDocument::CLAIMED, AccessDocument::BANKED].freeze

  # Two queries for the whole list, plus the arrival window.
  #
  # find_sap_for_person_ids is upstream's findWAPForPersonIds: the earliest
  # dated SAP or credential, preferring one already claimed or submitted.
  def preload(entries)
    person_ids = ids(entries)
    @saps = AccessDocument.find_sap_for_person_ids(person_ids)
    # Every any-time credential the write would reach, not just the one the
    # candidate rule picks out. update_saps_for_person sets access_any_time on
    # ALL of a person's qualified, claimed and banked passes and credentials, so
    # checking only the candidate let a date silently revoke any-time access on
    # a credential no preview row ever named -- the exact loss the refusal below
    # exists to prevent. Four columns: all the refusal does is name the document.
    @any_time = AccessDocument.where(person_id: person_ids,
                                     type: AccessDocument::STAFF_CREDENTIAL,
                                     status: WRITTEN_STATUSES,
                                     access_any_time: true)
                              .select(:id, :person_id, :type, :status)
                              .group_by(&:person_id)
    @day_low, @day_high = TicketingManagement.sap_day_range
  end

  def decide(entry)
    anytime, access_date, problem = parse(entry)
    return entry.decide(:invalid, problem) if problem

    sap = @saps[entry.person.id]
    return entry.decide(:invalid, "No SAP or Staff Credential to update") unless sap
    return entry.decide(:invalid, "#{document_label(sap)} has already been submitted") if submitted?(sap)

    problem = narrowed_access(entry, sap, anytime, access_date)
    return entry.decide(:invalid, problem) if problem

    # No :no_change verdict, ever. The write reaches every SAP and credential the
    # person holds and the candidate is the only one that was looked at, so
    # "already set" would be a claim about rows no one read.
    return entry.decide(:change, "Sets #{requested_access(anytime, access_date)}") unless dated?(sap)

    entry.decide(:replace, "#{document_label(sap)} gives access #{existing_access(sap)}. " \
                           "Sets #{requested_access(anytime, access_date)}")
  end

  def apply(entry)
    anytime, access_date, = parse(entry)

    AccessDocument.update_saps_for_person(entry.person.id, anytime ? nil : access_date, anytime, reason)
  end

  private

  # Returns [anytime, access_date, refusal]. Upstream reads data[0] and ignores
  # everything after it; a second column is refused here instead, because a
  # column that is silently dropped is how a reader comes away believing
  # something they typed took effect.
  def parse(entry)
    values = columns(entry)
    return [false, nil, "missing access type"] if values.empty?
    return [false, nil, "Unexpected additional data. This action takes a callsign and one date"] if values.many?

    input = values.first
    return [true, nil, nil] if input.casecmp?(ANY)

    access_date, problem = parse_date(input)
    return [false, nil, problem] if problem

    [false, access_date, in_window(access_date, input)]
  end

  # The four-character guard is borrowed from the ticket action's access date
  # for the same reason: "2026" parses as 20:26 today, and during August today
  # sits inside the arrival window, so a year typed here would be accepted as a
  # date no one meant. Refusing anything that short also refuses "8/10", which
  # is ambiguous in a way YYYY-MM-DD is not.
  def parse_date(input)
    invalid = "Invalid date [#{input}] — use YYYY-MM-DD, or any"
    return [nil, invalid] if input.length <= 4

    parsed = begin
      Time.zone.parse(input)
    rescue ArgumentError
      nil
    end

    parsed ? [parsed, nil] : [nil, invalid]
  end

  # Arrival is an August question: the window is a span of days read from the
  # TAS_SAPDateRange setting, which is where the rest of ticketing reads it.
  #
  # @return [String, nil] the refusal, or nil when the date is inside the window
  def in_window(access_date, input)
    return nil if access_date.year == year && access_date.month == 8 &&
                  access_date.day >= @day_low && access_date.day <= @day_high

    "Access must fall between #{window_day(@day_low)} and #{window_day(@day_high)} [#{input}]"
  end

  def window_day(day) = format("%<year>d-08-%<day>02d", year:, day:)

  # Upstream's two refusals, both only asked when a date is being set: anytime
  # access is never narrowed by accident, and a date is never pushed later than
  # the one already on file.
  #
  # The first is asked of every credential the write reaches rather than of the
  # candidate alone -- the candidate rule prefers a claimed or submitted row,
  # which is routinely not the any-time one.
  #
  # @return [String, nil]
  def narrowed_access(entry, sap, anytime, access_date)
    return nil if anytime

    unrestricted = @any_time[entry.person.id]&.first
    if unrestricted
      return "#{document_label(unrestricted)} gives access at any time. A date would take that away."
    end

    return nil unless sap.access_date && sap.access_date < access_date

    "#{document_label(sap)} already gives access on #{format_date(sap.access_date)}, earlier than " \
      "#{format_date(access_date)}. Access is never pushed back."
  end

  def submitted?(sap) = sap.status == AccessDocument::SUBMITTED

  def dated?(sap) = sap.access_any_time || sap.access_date.present?

  def existing_access(sap) = sap.access_any_time ? "at any time" : "on #{format_date(sap.access_date)}"

  def requested_access(anytime, access_date)
    anytime ? "access at any time" : "access on #{format_date(access_date)}"
  end

  def document_label(document) = "#{document.type_label} #{document.display_ref} (#{document.status})"
end
