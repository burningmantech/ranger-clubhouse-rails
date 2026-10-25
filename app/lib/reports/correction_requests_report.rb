# frozen_string_literal: true

# Timesheet corrections and missing-entry requests still waiting on a decision
# (Ember reports/timesheet-correction-requests port).
#
# Two tables answer one question -- a ranger says their hours are wrong, what
# should they be? -- so the page merges them. A Timesheet pending review is a
# correction to an entry that exists; a TimesheetMissing is a request for one
# that was never turned in. Pending only on both sides: an approved or rejected
# request has already been decided and is no one's outstanding volunteer.
#
# Ported from app/Lib/Reports/CombinedTimesheetCorrectionRequestsReport.php.
# Upstream returns each request's notes in its payload and then never draws
# them, so a reviewer has to open a person page per row to find out what is
# being asked. They are carried here and shown.
class CorrectionRequestsReport
  # Prices through TimesheetCredits rather than TimesheetYearReport: this page
  # is gated whole-page by role and honours no per-position visibility rule, so
  # taking the concern that carries those rules -- to reach one pricing method
  # -- would say it does.
  #
  # notes are the reason the request was made, oldest first, admin notes
  # excluded -- the `notes` association is already scoped that way, because an
  # admin note is the reviewer talking to other reviewers rather than the
  # ranger explaining themselves.
  #
  # person is nil for a deleted ranger; callsign speaks for both.
  Entry = Data.define(:id, :missing, :person, :person_id, :callsign,
                      :position_title, :on_duty, :off_duty, :duration,
                      :credits, :notes) do
    def missing? = missing

    def letter = callsign[0].to_s.upcase

    # Total, so the table cannot reshuffle between two reads: sort_by is not
    # stable, and a ranger who filed both a correction and a missing-entry
    # request for the same shift -- the double-request case this page is opened
    # for -- ties on callsign and on_duty alike. Corrections sort ahead of
    # missing entries, then by id.
    def sort_key = [callsign.downcase, on_duty, missing ? 1 : 0, id]

    # Both sides draw their ids from their own sequence, so the model has to be
    # part of any id built from them or two unrelated rows collide.
    def dom_key = "#{missing ? "missing" : "timesheet"}-#{id}"
  end

  Report = Data.define(:year, :entries) do
    def empty? = entries.empty?

    # The letters the report actually holds. A letter no one's callsign starts
    # with is a filter that can only return nothing.
    #
    # A blank is dropped rather than offered: its option would carry the same
    # empty value as "All callsigns" and be indistinguishable from it, and
    # letter_filter refuses a zero-length param anyway.
    def letters = entries.map(&:letter).reject(&:empty?).uniq.sort
  end

  class << self
    def execute(year:)
      corrections = pending_timesheets(year)
      missing = pending_missing(year)

      # One cache warm for the year, two hashes out. Priced together because
      # both sides read the same year's credits; kept apart because a Timesheet
      # id and a TimesheetMissing id come from different sequences and collide
      # freely, and a merged hash would price one row with the other's credits.
      correction_credits, missing_credits =
        TimesheetCredits.credits_by_collection(corrections, missing)

      entries = build(corrections, correction_credits, missing: false) +
                build(missing, missing_credits, missing: true)

      # Upstream's final usort: case-insensitive callsign, then check-in order
      # within a ranger. See Entry#sort_key for why the key runs past those two.
      Report.new(year:, entries: entries.sort_by(&:sort_key))
    end

    private

    # with_off_duty is upstream's whereNotNull: a pending entry still running
    # has no span to correct yet, and duration would be measured against now.
    def pending_timesheets(year)
      Timesheet.for_year(year)
               .where(review_status: Timesheet::STATUS_PENDING)
               .with_off_duty
               .includes(:person, :position, notes: :create_person)
               .to_a
    end

    # The scopes directly rather than retrieve_for_person_or_all_for_year: that
    # loads the partner and reviewer rows this page never draws -- and on the
    # Laravel side serializing them costs a metaphone lookup and a shift search
    # per row -- while loading none of the notes it does.
    def pending_missing(year)
      TimesheetMissing.for_year(year)
                      .pending
                      .includes(:person, :position, notes: :create_person)
                      .to_a
    end

    def build(rows, credits, missing:)
      rows.map do |row|
        person = row.person

        Entry.new(id: row.id,
                  missing:,
                  person:,
                  person_id: row.person_id,
                  callsign: person&.callsign || "Deleted ##{row.person_id}",
                  # The Laravel-shared schema carries no FK, so position reads
                  # nil even though the association is not optional.
                  position_title: row.position&.title,
                  on_duty: row.on_duty,
                  off_duty: row.off_duty,
                  duration: row.duration,
                  credits: credits.fetch(row.id, 0.0),
                  # sort_by on the loaded association rather than an `ordered`
                  # scope, which would re-query past the includes.
                  notes: row.notes.sort_by(&:created_at))
      end
    end
  end
end
