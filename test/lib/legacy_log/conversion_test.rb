# frozen_string_literal: true

require "test_helper"

# Synthetic log rows only: the log is personal data and never enters test/.
class LegacyLog::ConversionTest < ActiveSupport::TestCase
  OCCURRED = Time.zone.parse("2015-06-01 12:00:00")

  setup do
    Clubhouse1Log.delete_all
    LegacyLog.delete_all
    @actor = person(:active_ranger)
    @subject = person(:auditor_ranger)
  end

  # @return [Integer] the new log row's id
  def log(event, user_person_id: @actor.id, current_person_id: @subject.id)
    Clubhouse1Log.insert!({ event:, occurred: OCCURRED, user_person_id:, current_person_id: })
    Clubhouse1Log.maximum(:id)
  end

  def run_conversion(**options)
    LegacyLog::Conversion.new(output: StringIO.new, **options).run
  end

  test "writes a SQL statement as unknown, with the session's person as its target" do
    statement = "=person.status=alpha@id=#{@subject.id}"
    kept = log(statement)

    conversion = run_conversion

    row = LegacyLog.find_by!(log_id: kept)
    assert_equal "unknown", row.event
    assert_equal statement, row.message
    assert_equal({ "event" => statement, "log_id" => kept, "target_source" => "session" }, row.data)
    assert_equal @actor.id, row.person_id
    assert_equal @subject.id, row.target_person_id
    assert_equal OCCURRED, row.created_at
    assert_equal 1, conversion.counts[:unknown]
    assert_equal 0, conversion.counts[:converted]
  end

  test "skips events, diagnostics and session purges, and counts each" do
    log("#login rangers")
    log("!DB SQL error")
    log("-sessions@expires<NOW()")
    log("=person.status=alpha@id=1")

    conversion = run_conversion

    assert_equal 1, LegacyLog.count
    assert_equal({ read: 4, events: 1, diagnostics: 1, sessions: 1, unknown: 1 },
                 conversion.counts.slice(:read, :events, :diagnostics, :sessions, :unknown))
  end

  test "a person id of zero is read as no one" do
    kept = log("=person.status=alpha@id=1", user_person_id: 0, current_person_id: 0)

    run_conversion

    row = LegacyLog.find_by!(log_id: kept)
    assert_nil row.person_id
    assert_nil row.target_person_id
  end

  test "a second run leaves the same rows and no duplicates" do
    ids = Array.new(12) { |n| log("+personslot(personid,slotid)(#{n + 1},#{n + 1})") }
    rows = -> { LegacyLog.order(:log_id).map(&:attributes) }
    run_conversion
    before = rows.call

    run_conversion

    assert_equal before, rows.call
    assert_equal ids.sort, LegacyLog.pluck(:log_id).sort
  end

  test "a dry run reports without writing" do
    log("=person.status=alpha@id=1")

    conversion = run_conversion(dry_run: true)

    assert_equal 0, LegacyLog.count
    assert_equal 1, conversion.counts[:unknown]
    assert_match "(dry run)", conversion.report
  end

  test "from and to bound the log ids" do
    log("=person.status=alpha@id=1")
    second = log("=person.status=alpha@id=2")
    log("=person.status=alpha@id=3")

    run_conversion(from_id: second, to_id: second)

    assert_equal [second], LegacyLog.pluck(:log_id)
  end

  test "the report counts each family and shows three unknown examples" do
    4.times { |n| log("=person.status=alpha@id=#{n + 1}") }
    log("+personslot(personid,slotid)(1,2)")
    log("+widget(a)(1)")

    conversion = run_conversion

    assert_equal({ converted: 0, unknown: 4 }, conversion.families["update person"].slice(:converted, :unknown))
    assert_equal 3, conversion.families["update person"][:examples].size
    assert_match(/\ALegacy log conversion: 6 rows read/, conversion.report)
    assert_match "Skipped: 0 events (#), 0 diagnostics (!), 0 sessions (-sessions)", conversion.report
    assert_match "Unknown: 6 (100.0% of 6)", conversion.report
    assert_match "update person: 0 / 4", conversion.report
    assert_match "insert person_slot: 0 / 1", conversion.report
    assert_match "insert (widget): 0 / 1", conversion.report
  end
end
