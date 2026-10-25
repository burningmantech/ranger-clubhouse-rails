# frozen_string_literal: true

require "test_helper"

class CorrectionStatsReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # Clear of the timesheet fixtures, which occupy 2023-2025, and above the 2018
  # floor. travel_to makes it the current year so nothing reads as the future.
  YEAR = 2031

  setup do
    Current.reset
    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    @owner = person(:active_ranger)
    @other_owner = person(:inactive_ranger)
    @reviewer = person(:echelon_ranger)
    @other_reviewer = person(:auditor_ranger)
    @position = positions(:ood_position)
    @other_position = positions(:mentor_lead)
  end

  teardown do
    travel_back
    Current.reset
  end

  # --- factories ---------------------------------------------------------

  def as_person(person)
    was = Current.person
    Current.person = person
    yield
  ensure
    Current.person = was
  end

  # additional_notes is not optional: Timesheet#is_reason_provided? rejects an
  # entry that arrives with neither a user note nor a reason.
  def create_entry!(person: @owner, position: @position, on_duty: @now)
    as_person(person) do
      Timesheet.create!(person:, position:, on_duty:, off_duty: on_duty + 6.hours,
                        review_status: Timesheet::STATUS_APPROVED,
                        additional_notes: "Signed in on the wrong position")
    end
  end

  # A review as the audit trail records it: the log carries the old and new
  # status, its person_id is the entry's owner and its create_person_id is
  # whoever changed it.
  #
  # `year:` is deliberately settable and deliberately ignored by the report --
  # the column holds the event's year, not the year the log was written.
  def log_review!(timesheet:, owner: @owner, reviewer: @reviewer,
                  from: Timesheet::STATUS_PENDING, to: Timesheet::STATUS_APPROVED,
                  at: @now, data: nil, year: nil)
    TimesheetLog.create!(action: TimesheetLog::UPDATE,
                         person_id: owner&.id || owner,
                         create_person_id: reviewer.is_a?(Person) ? reviewer.id : reviewer,
                         timesheet_id: timesheet&.id,
                         data: data || { "review_status" => [from, to] },
                         year: year || at.year,
                         created_at: at)
  end

  # One reviewed correction, entry and log together.
  def create_correction!(owner: @owner, position: @position, on_duty: @now, **log_args)
    entry = create_entry!(person: owner, position:, on_duty:)
    log_review!(timesheet: entry, owner:, **log_args)
    entry
  end

  def create_missing!(person: @owner, position: @position, on_duty: @now,
                      reviewer: @reviewer,
                      review_status: TimesheetMissing::STATUS_APPROVED)
    reviewer_id = reviewer.is_a?(Person) ? reviewer.id : reviewer

    as_person(person) do
      TimesheetMissing.create!(person_id: person.id, create_person_id: person.id,
                               position_id: position.id, on_duty:,
                               off_duty: on_duty + 6.hours, partner: "none",
                               review_status:, reviewer_person_id: reviewer_id,
                               additional_notes: "Never got signed in for this shift")
    end
  end

  def report(year = YEAR) = CorrectionStatsReport.execute(year:)

  # --- corrections -------------------------------------------------------

  test "an approved and a rejected correction are counted by their outcome" do
    create_correction!
    create_correction!(to: Timesheet::STATUS_REJECTED)

    stats = report.corrections

    assert_equal 1, stats.approved
    assert_equal 1, stats.rejected
    assert_equal 2, stats.decided
  end

  # Anything that is not a decision is somebody moving the entry along, not
  # reviewing it.
  test "transitions that are not a decision are ignored" do
    create_correction!(to: Timesheet::STATUS_VERIFIED)
    create_correction!(to: Timesheet::STATUS_UNVERIFIED)
    create_correction!(to: Timesheet::STATUS_PENDING)

    assert_equal 0, report.corrections.decided
  end

  # The prefilter is a LIKE on the JSON text; a log with no review_status in it
  # never reaches the decoder.
  test "logs that record something other than a review are ignored" do
    entry = create_entry!
    log_review!(timesheet: entry, data: { "off_duty" => ["2031-08-26 12:00:00",
                                                         "2031-08-26 18:00:00"] })

    assert_equal 0, report.corrections.decided
    assert report.empty?
  end

  # A ranger approving their own entry is not review activity, and upstream
  # skips it before counting anything.
  test "a ranger deciding their own entry is not counted" do
    create_correction!(reviewer: @owner)

    assert_equal 0, report.corrections.decided
    assert_empty report.reviewers
  end

  # Upstream counts the decision but cannot name who made it -- the reviewers
  # table is keyed on a person id it does not have.
  test "a decision with no recorded author counts but names no reviewer" do
    create_correction!(reviewer: nil)

    assert_equal 1, report.corrections.approved
    assert_empty report.reviewers
  end

  # Upstream's inner join: the entry is gone, so its reviews are gone too.
  test "reviews of a deleted entry drop out of the correction counts" do
    entry = create_correction!
    entry.delete

    assert_equal 0, report.corrections.decided
  end

  test "an entry deleted after being logged is counted as deleted" do
    entry = create_correction!
    log_review!(timesheet: entry, to: Timesheet::STATUS_REJECTED)
    entry.delete

    # Two logs, one entry: the count is of entries, not of their logs.
    assert_equal 1, report.entries_deleted
  end

  test "an entry that still exists is not counted as deleted" do
    create_correction!

    assert_equal 0, report.entries_deleted
  end

  # Upstream counts every transition rather than every entry, so an entry
  # bounced back and forth counts each time. Kept deliberately: the page
  # measures decisions made, not entries settled.
  test "an entry reviewed twice counts twice" do
    entry = create_correction!
    log_review!(timesheet: entry, from: Timesheet::STATUS_APPROVED,
                to: Timesheet::STATUS_REJECTED)

    stats = report.corrections

    assert_equal 1, stats.approved
    assert_equal 1, stats.rejected
  end

  # --- the off-by-one upstream ships -------------------------------------

  # Upstream seeds each counter at 1 and then adds 1 for that same first row, so
  # its lists read one high per row. This port counts plainly; the numbers here
  # are the true ones and are expected to sit one below Clubhouse 2's.
  test "a position with three corrections is listed as three, not four" do
    3.times { create_correction! }

    tally = report.corrections.top_positions.sole

    assert_equal @position.id, tally.position_id
    assert_equal 3, tally.total
  end

  test "a ranger with two corrections is listed as two, not three" do
    2.times { create_correction! }

    tally = report.corrections.top_people.sole

    assert_equal @owner.id, tally.person_id
    assert_equal 2, tally.total
  end

  # --- top lists ---------------------------------------------------------

  test "top positions and rangers are ordered by how many requests they hold" do
    2.times { create_correction! }
    create_correction!(owner: @other_owner, position: @other_position)

    positions = report.corrections.top_positions
    people = report.corrections.top_people

    assert_equal [@position.id, @other_position.id], positions.map(&:position_id)
    assert_equal [2, 1], positions.map(&:total)
    assert_equal [@owner.id, @other_owner.id], people.map(&:person_id)
  end

  test "top lists hold at most twenty rows" do
    25.times do |index|
      create_correction!(on_duty: @now + index.days,
                         position: Position.create!(title: "Test Position #{index}",
                                                    type: "Frontline"))
    end

    assert_equal CorrectionStatsReport::TOP_LIMIT, report.corrections.top_positions.size
  end

  # The tally is keyed on an id, and a position row can be gone while the id
  # lives on in the timesheet -- the Laravel-shared schema carries no keys.
  test "a deleted position is named by its id rather than dropped" do
    position = Position.create!(title: "Vanishing Position", type: "Frontline")
    create_correction!(position:)
    position.delete

    tally = report.corrections.top_positions.sole

    assert_nil tally.title
    assert_equal "Deleted position ##{position.id}", tally.label
  end

  # --- missing-entry requests --------------------------------------------

  test "missing requests are counted by their outcome" do
    create_missing!
    create_missing!(person: @other_owner, review_status: TimesheetMissing::STATUS_REJECTED)

    stats = report.missing

    assert_equal 1, stats.approved
    assert_equal 1, stats.rejected
    assert_equal 2, stats.total
  end

  # Upstream's filter is `reviewer_person_id != person_id`, which in SQL is NULL
  # whenever there is no reviewer -- so a request no one has picked up yet is
  # missing from every number on this side, the total included. Roughly a third
  # of a recent year's requests. Ported deliberately; the page says these are
  # the requests that reached a reviewer and points at the sibling page for the
  # rest.
  test "a request no one has reviewed is excluded from every missing count" do
    create_missing!(reviewer: nil, review_status: TimesheetMissing::STATUS_PENDING)

    stats = report.missing

    assert_equal 0, stats.total
    assert_equal 0, stats.decided
    assert_empty stats.top_positions
    assert_empty stats.top_people
  end

  test "a ranger reviewing their own missing request is excluded" do
    create_missing!(reviewer: @owner)

    assert_equal 0, report.missing.total
  end

  # A request assigned to a reviewer and left pending is in the total but not in
  # either outcome -- the only way total and decided come apart.
  test "a request left pending with a reviewer counts as undecided" do
    create_missing!(review_status: TimesheetMissing::STATUS_PENDING)

    stats = report.missing

    assert_equal 1, stats.total
    assert_equal 0, stats.decided
    assert_equal 1, stats.undecided
  end

  # The card's bar has to divide the same population its chips enumerate. Over
  # `decided` these would read 100%/0% while a "Still open 1" chip sat beside
  # them.
  test "the meter shares are measured against every request, not just decided ones" do
    create_missing!
    create_missing!(on_duty: @now + 1.day, review_status: TimesheetMissing::STATUS_PENDING)

    stats = report.missing

    assert_equal 50.0, stats.approved_percent
    assert_equal 0.0, stats.rejected_percent
    assert_equal 50.0, stats.undecided_percent
  end

  # 0/0 is NaN and NaN.round(1) returns NaN rather than raising, so an
  # unguarded reader would render "width: NaN%" and a silently blank bar.
  test "the meter shares are zero rather than NaN when there is nothing to divide" do
    stats = report.missing

    assert_equal 0, stats.total
    assert_equal 0.0, stats.approved_percent
    assert_equal 0.0, stats.rejected_percent
    assert_equal 0.0, stats.undecided_percent
  end

  # No status filter on these two, as upstream: they ask where requests come
  # from, not how they ended.
  test "top missing lists count requests whatever their outcome" do
    create_missing!(review_status: TimesheetMissing::STATUS_PENDING)
    create_missing!(on_duty: @now + 1.day)

    assert_equal 2, report.missing.top_positions.sole.total
    assert_equal 2, report.missing.top_people.sole.total
  end

  # --- reviewers ---------------------------------------------------------

  test "a reviewer's row totals both kinds of request" do
    create_correction!
    create_correction!(to: Timesheet::STATUS_REJECTED)
    create_missing!
    create_missing!(person: @other_owner, review_status: TimesheetMissing::STATUS_REJECTED)

    row = report.reviewers.sole

    assert_equal @reviewer.id, row.person_id
    assert_equal 1, row.corrections_approved
    assert_equal 1, row.corrections_rejected
    assert_equal 2, row.corrections_total
    assert_equal 1, row.missing_approved
    assert_equal 1, row.missing_rejected
    assert_equal 2, row.missing_total
    assert_equal 4, row.grand_total
  end

  test "reviewers of either kind of request all get a row, ordered by callsign" do
    create_correction!(reviewer: @other_reviewer)
    create_missing!(reviewer: @reviewer)

    expected = [@reviewer, @other_reviewer].map(&:callsign).sort_by(&:downcase)

    assert_equal expected, report.reviewers.map { |row| row.person.callsign }
  end

  # Upstream drops the row, which loses decisions the summary above has already
  # counted. The row stays here; the view spells the missing person out.
  test "a reviewer whose person row is gone keeps their row" do
    create_correction!(reviewer: 999_999)

    row = report.reviewers.sole

    assert_equal 999_999, row.person_id
    assert_nil row.person
    assert_equal 1, row.corrections_approved
  end

  # --- year scoping ------------------------------------------------------

  # Corrections are counted under the year the decision was made, even when the
  # entry belongs to an earlier event.
  test "a correction is counted under the year it was decided" do
    entry = create_entry!(on_duty: @now - 1.year)
    log_review!(timesheet: entry, at: @now)

    assert_equal 1, report(YEAR).corrections.decided
    assert_equal 0, report(YEAR - 1).corrections.decided
  end

  # The log's own year column holds the event year, not the year it was written.
  # Counting on it instead of created_at would move this row a year.
  test "the log's year column does not decide which year counts it" do
    entry = create_entry!
    log_review!(timesheet: entry, at: @now, year: YEAR - 5)

    assert_equal 1, report(YEAR).corrections.decided
    assert_equal 0, report(YEAR - 5).corrections.decided
  end

  # Missing requests are counted under the shift's year, whenever they were
  # filed or decided.
  test "a missing request is counted under the year of its shift" do
    create_missing!(on_duty: @now - 1.year)

    assert_equal 0, report(YEAR).missing.total
    assert_equal 1, report(YEAR - 1).missing.total
  end

  test "the entry total counts the year's timesheets" do
    create_entry!
    create_entry!(person: @other_owner)
    create_entry!(on_duty: @now - 1.year)

    assert_equal 2, report.timesheet_total
  end

  # --- empty -------------------------------------------------------------

  test "a year with no correction activity is empty" do
    create_entry!

    result = report

    assert_predicate result, :empty?
    assert_equal 1, result.timesheet_total
    assert_empty result.reviewers
  end

  test "a year with a decided request is not empty" do
    create_correction!

    assert_not_predicate report, :empty?
  end
end
