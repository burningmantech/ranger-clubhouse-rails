# frozen_string_literal: true

# Rangers who look like they still need a Setup Access Pass.
#
# A SAP lets someone onto the playa before gate opens. Most people get one
# alongside their ticket, but anyone who did not qualify at the time — no ticket
# yet, status not settled — never got one, and nothing goes back to check on
# them later. This report is that check.
#
# Port of the Laravel GrantPasses::findRangersWhoNeedWAPs behind the Ember
# vc/access-documents/waps page. The DB still spells a SAP "work_access_pass"
# (AccessDocument::SAP); upstream's has_rpt flag is has_spt here.
class SapCandidatesReport
  # tickets holds the person's special price tickets when has_spt; years and
  # schedule are only populated for people who make the report.
  Row = Data.define(:person, :has_spt, :tickets, :years, :schedule)

  # One current-year shift sign-up.
  SignUp = Data.define(:begins, :position_title, :description) do
    # Reads come back cast into Time.zone, an hour ahead of the stored wall
    # clock for half the year; getlocal returns to the clock the shift was
    # scheduled against.
    def begins_label
      begins.getlocal.strftime(DateTimeHelper::MONTH_DAY_TIME)
    end
  end

  # The three document types that can settle the question: a SAP outright, or a
  # staff credential, which is an event ticket and a SAP in one.
  COVERING_TYPES = [AccessDocument::SAP, *AccessDocument::REGULAR_TICKET_TYPES].freeze

  # Statuses whose people count as having volunteered recently. Narrower than
  # the sign-up list further down on purpose: a retiree's shifts from three
  # years ago say nothing about this year, but a sign-up does.
  WORKED_STATUSES = [Person::ACTIVE, Person::INACTIVE].freeze

  # The earliest event year the look-back covers: the third event before this
  # one. Events, not years, so from 2024 it reaches back over 2020 and 2021 to
  # 2019, as upstream's table of those years did.
  #
  # @param year [Integer]
  # @return [Integer]
  def self.start_year(year) = EventYearSpan.last_years(3, through: year - 1).first

  # @param year [Integer]
  # @return [Array<Row>] sorted by callsign, case-insensitively
  def self.execute(year)
    new(year).execute
  end

  def initialize(year)
    @year = year
    @start_year = self.class.start_year(year)
  end

  def execute
    return [] if pool_ids.empty?

    candidates = select_candidates
    return [] if candidates.empty?

    ids = candidates.map { |person, _| person.id }
    years = years_by_person(ids)
    schedules = schedules_by_person(ids)

    candidates.map { |person, tickets|
      Row.new(person:, has_spt: tickets.any?, tickets:,
              years: years[person.id] || [], schedule: schedules[person.id] || [])
    }.sort_by { |row| row.person.callsign.downcase }
  end

  private

  # Everyone worth checking: recent volunteers plus this year's sign-ups.
  def pool_ids
    @pool_ids ||= (signed_up_ids | worked_ids).to_a
  end

  # A range on on_duty rather than YEAR(on_duty), which MariaDB cannot index.
  # Time.local, not Time.zone: timesheets are stored as machine-local wall
  # clock, so a zoned boundary lands an hour off.
  def window_start
    @window_start ||= Time.local(@start_year)
  end

  def worked_ids
    Person.where(status: WORKED_STATUSES)
          .joins(:timesheet)
          .where(timesheet: { on_duty: window_start.. })
          .distinct
          .pluck(:id)
  end

  # Kept as a Set: the selection loop asks about membership one person at a time.
  def signed_up_ids
    @signed_up_ids ||= Person.where(status: Person::ACTIVE_STATUSES)
                             .joins(:slot)
                             .where(slot: { begins_year: @year })
                             .distinct
                             .pluck(:id)
                             .to_set
  end

  # One read for the whole pool, and only the types that can settle the
  # question, which is what makes the loop below short.
  #
  # Upstream spelled out qualified/claimed/submitted for a SAP and the full
  # CURRENT_STATUSES for tickets, as if a banked SAP were a case worth handling.
  # SAPs are never banked — banking carries a ticket to a future event, which a
  # pass for one event cannot do — so the two lists were always the same set.
  def documents_by_person
    AccessDocument.where(type: COVERING_TYPES, status: AccessDocument::CURRENT_STATUSES)
                  .where(person_id: pool_ids)
                  .select(:id, :person_id, :type, :status)
                  .group_by(&:person_id)
  end

  # @return [Array<[Person, Array<AccessDocument>]>] each candidate with their
  #   special price tickets, empty when they hold nothing at all
  def select_candidates
    documents = documents_by_person

    Person.where(id: pool_ids).select(:id, :callsign, :status, :email).filter_map do |person|
      docs = documents[person.id]

      # Nothing on file. Recent shifts alone are not a reason to issue a pass —
      # a sign-up for this year is.
      next (signed_up_ids.include?(person.id) ? [person, []] : nil) if docs.nil?

      # Already covered: a SAP outright, or a staff credential, which is an
      # event ticket and a SAP in one.
      next if docs.any? { |doc| doc.type == AccessDocument::SAP }
      next if docs.any? { |doc| doc.type == AccessDocument::STAFF_CREDENTIAL }

      # Only special price tickets can be left — the read above pulls nothing
      # else. Holding one means they are coming, so they need a way in.
      # (Upstream had a fourth branch here for people with documents but no
      # ticket; the same reasoning makes it unreachable, so it is dropped.)
      [person, docs]
    end
  end

  # Distinct event years with any timesheet entry, deliberately unfiltered.
  # Person#years_as_ranger would be wrong here: it drops training positions and
  # short shifts, and this report is asking "was this person around", not "did
  # the year count towards their record".
  def years_by_person(ids)
    Timesheet.where(person_id: ids, on_duty: window_start..)
             .distinct
             .pluck(:person_id, Arel.sql("YEAR(on_duty)"))
             .group_by(&:first)
             .transform_values { |pairs| pairs.map(&:last).sort }
  end

  def schedules_by_person(ids)
    PersonSlot.joins(slot: :position)
              .where(person_id: ids, slot: { begins_year: @year })
              .order("slot.begins")
              .pluck(:person_id, "slot.begins", "position.title", "slot.description")
              .group_by(&:first)
              .transform_values { |rows|
                rows.map { |_, begins, title, description| SignUp.new(begins:, position_title: title, description:) }
              }
  end
end
