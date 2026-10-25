# frozen_string_literal: true

require "test_helper"

class PogStatsReportTest < ActiveSupport::TestCase
  YEAR = 2025

  setup do
    @issuer = person(:active_ranger)
    @recipient = person(:echelon_ranger)
  end

  test "a year with no pogs is empty" do
    assert_predicate PogStatsReport.execute(year: YEAR), :empty?
  end

  test "types count issued pogs with the redeemed among them, and cancelled apart" do
    PersonPog.insert_all([row, row, row(status: PersonPog::STATUS_CANCELLED),
                          row(pog: PersonPog::POG_HALF_MEAL, status: PersonPog::STATUS_REDEEMED),
                          row(pog: PersonPog::POG_HALF_MEAL)])

    report = PogStatsReport.execute(year: YEAR)

    assert_equal [[PersonPog::POG_MEAL, 2, 0, 1], [PersonPog::POG_HALF_MEAL, 2, 1, 0]],
                 report.types.map { |type| [type.pog, type.issued, type.redeemed, type.cancelled] }
    assert_equal [4, 1, 1], [report.issued, report.redeemed, report.cancelled]
    assert_equal 50, report.type_share(report.types.first)
  end

  # Time.local, not Time.zone: rows are stored on the process clock, and the
  # day is read from what is stored.
  test "a day is the stored calendar date, either side of midnight" do
    PersonPog.insert_all([row(issued_at: Time.local(YEAR, 8, 27, 23, 59)),
                          row(issued_at: Time.local(YEAR, 8, 28, 0, 1), pog: PersonPog::POG_SHOWER),
                          row(issued_at: Time.local(YEAR, 8, 28, 9, 0)),
                          row(issued_at: Time.local(YEAR, 8, 28, 10, 0), status: PersonPog::STATUS_CANCELLED)])

    report = PogStatsReport.execute(year: YEAR)

    assert_equal [[Date.new(YEAR, 8, 27), { PersonPog::POG_MEAL => 1 }],
                  [Date.new(YEAR, 8, 28), { PersonPog::POG_SHOWER => 1, PersonPog::POG_MEAL => 1 }]],
                 report.days.map { |day| [day.date, day.counts] }
    assert_equal Date.new(YEAR, 8, 28), report.busiest_day.date
    assert_equal 50, report.day_share(report.days.first)
  end

  # Ids above any fixture stand in for people whose rows were deleted.
  test "a top list ranks by count, stops at ten, and keeps a deleted person" do
    gone = (990_001..990_011).to_a
    PersonPog.insert_all(gone.map { |id| row(issued_by_id: id) } +
                         [row(issued_by_id: 990_011), row(issued_by_id: 990_011),
                          row(issued_by_id: @issuer.id), row(issued_by_id: @issuer.id),
                          row(issued_by_id: 990_009, status: PersonPog::STATUS_CANCELLED)])

    report = PogStatsReport.execute(year: YEAR)

    assert_equal 12, report.issuer_count
    assert_equal [[990_011, 3], [@issuer.id, 2]] + (990_001..990_008).map { |id| [id, 1] },
                 report.issuers.map { |row| [row.person_id, row.total] },
                 "ties are cut by id, and a cancelled pog never counts"
    assert_nil report.issuers.first.person
    assert_equal @issuer, report.issuers.second.person
  end

  test "the linked share counts issued pogs recorded with a shift" do
    PersonPog.insert_all([row(timesheet_id: 1), row, row,
                          row(timesheet_id: 2, status: PersonPog::STATUS_CANCELLED)])

    report = PogStatsReport.execute(year: YEAR)

    assert_equal [1, 33], [report.linked, report.linked_percent]
  end

  # Rounding alone would read 0% with one linked, and 100% with one missing.
  test "a share is never 0% while there is something, nor 100% while something is missing" do
    report = result(issued: 250, linked: 1)
    assert_equal 1, report.linked_percent
    assert_equal 99, result(issued: 250, linked: 249).linked_percent
    assert_equal 100, result(issued: 250, linked: 250).linked_percent
    assert_equal 0, result(issued: 250, linked: 0).linked_percent
    assert_equal 0, result(issued: 0, linked: 0).linked_percent
  end

  # Clubhouse 2 stored type and status unchecked. A row PersonPog does not know
  # is left out everywhere, and one spelled differently is counted everywhere --
  # never in some sections and not others.
  test "every section counts the same rows" do
    PersonPog.insert_all([row(timesheet_id: 1),
                          row(pog: "Meal", timesheet_id: 2),
                          row(pog: "lunch", timesheet_id: 3),
                          row(status: "lost", timesheet_id: 4)])

    report = PogStatsReport.execute(year: YEAR)

    assert_equal [[PersonPog::POG_MEAL, 2]], report.types.map { |type| [type.pog, type.issued] }
    assert_equal [{ PersonPog::POG_MEAL => 2 }], report.days.map(&:counts)
    assert_equal [2, 2], [report.days.sole.total, report.linked]
    assert_equal 100, report.linked_percent
  end

  private

  # insert_all, not create!: the rows need ids no person has, and every row
  # must carry the same keys.
  def result(issued:, linked:)
    PogStatsReport::Result.new(
      types: [PogStatsReport::TypeCount.new(pog: PersonPog::POG_MEAL, issued:, redeemed: 0, cancelled: 0)],
      days: [], busiest_day: nil, issuers: [], recipients: [], issuer_count: 0, recipient_count: 0, linked:
    )
  end

  def row(**attrs)
    { person_id: @recipient.id, issued_by_id: @issuer.id, pog: PersonPog::POG_MEAL,
      status: PersonPog::STATUS_ISSUED, notes: "", timesheet_id: nil,
      issued_at: Time.local(YEAR, 8, 27, 12) }.merge(attrs)
  end
end
