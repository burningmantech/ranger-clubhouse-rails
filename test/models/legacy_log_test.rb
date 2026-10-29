# frozen_string_literal: true

require "test_helper"

class LegacyLogTest < ActiveSupport::TestCase
  include LegacyLogTestHelper

  setup do
    LegacyLog.delete_all
    @actor = person(:active_ranger)
    @subject = person(:auditor_ranger)
  end

  def ids(result)
    result[:legacy_logs].map(&:id)
  end

  test "nothing may be written through a record" do
    row = create_legacy_log

    assert_predicate row, :readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { row.update!(event: "changed") }
  end

  test "data is kept as JSON" do
    row = create_legacy_log(data: { "target_source" => "session" })

    assert_equal "session", row.data["target_source"]
    assert_equal "=person.status=alpha@id=1", row.data["event"]
  end

  test "the summary pairs an insert's columns with its values" do
    row = create_legacy_log(event: "person-slot-add", data: { "columns" => "personid,slotid", "values" => "687,386" })

    assert_equal "personid=687, slotid=386", row.summary
  end

  test "the summary leaves the values alone when a comma inside one breaks the pairing" do
    row = create_legacy_log(event: "person-message-create",
                 data: { "columns" => "personid,subject", "values" => "687,Hey,there" })

    assert_equal "687,Hey,there", row.summary
  end

  test "the summary reads an update's assignments and conditions, and a delete's conditions" do
    update = create_legacy_log(event: "person-update", data: { "set" => "status=alpha", "where" => "id=1578&status=prospective" })
    delete = create_legacy_log(event: "person-slot-remove", data: { "where" => "personid=687&slotid=15" })

    assert_equal "status=alpha where id=1578 and status=prospective", update.summary
    assert_equal "where personid=687 and slotid=15", delete.summary
  end

  test "the summary of an unknown row is the raw event" do
    row = create_legacy_log(statement: "=traineestatus.passed=0,notes=@id=LIMIT1")

    assert_equal "=traineestatus.passed=0,notes=@id=LIMIT1", row.summary
  end

  test "loads the session's people a page at a time" do
    create_legacy_log(event: "timesheet-update", data: { "session_person_id" => @subject.id })
    create_legacy_log(event: "timesheet-update", data: { "session_person_id" => 999_999 })
    create_legacy_log(event: "timesheet-update", data: { "set" => "offduty=NOW()" })

    rows = LegacyLog.find_for_query[:legacy_logs]

    assert_equal [nil, nil, @subject], rows.map(&:session_person)
  end

  test "narrows to who acted, and to who was acted upon" do
    mine = create_legacy_log(person: @actor, target: @subject)
    theirs = create_legacy_log(person: @subject, target: @actor)

    assert_equal [mine.id], ids(LegacyLog.find_for_query(person_id: @actor.id))
    assert_equal [theirs.id], ids(LegacyLog.find_for_query(target_person_id: @actor.id))
    assert_equal [mine.id], ids(LegacyLog.find_for_query(person_id: @actor.id, target_person_id: @subject.id))
  end

  test "narrows to a time range" do
    inside = create_legacy_log(created_at: Time.zone.parse("2015-06-01 12:00:00"))
    create_legacy_log(created_at: Time.zone.parse("2014-01-01 12:00:00"))
    create_legacy_log(created_at: Time.zone.parse("2016-01-01 12:00:00"))

    result = LegacyLog.find_for_query(start_time: Time.zone.parse("2015-01-01 00:00:00"),
                                      end_time: Time.zone.parse("2015-12-31 23:59:59"))

    assert_equal [inside.id], ids(result)
  end

  test "matches an exact event name, a pattern, or either" do
    update = create_legacy_log(event: "person-update")
    add = create_legacy_log(event: "person-slot-add")
    create_legacy_log(event: "unknown")

    assert_equal [update.id], ids(LegacyLog.find_for_query(events: ["person-update"]))
    assert_equal [add.id], ids(LegacyLog.find_for_query(events: ["person-slot-%"]))
    assert_equal [add.id, update.id].sort, ids(LegacyLog.find_for_query(events: ["person-update", "person-slot-%"])).sort
  end

  test "sorts newest first, the id breaking ties" do
    same_second = Time.zone.parse("2015-06-01 12:00:00")
    older = create_legacy_log(created_at: Time.zone.parse("2010-01-01 12:00:00"))
    first = create_legacy_log(created_at: same_second)
    second = create_legacy_log(created_at: same_second)

    assert_equal [second.id, first.id, older.id], ids(LegacyLog.find_for_query)
  end

  test "a full page says another follows, and the last page says none" do
    3.times { create_legacy_log }

    first_page = LegacyLog.find_for_query(page_size: 2)
    last_page = LegacyLog.find_for_query(page: 2, page_size: 2)

    assert_equal 2, first_page[:legacy_logs].size
    assert_equal 2, first_page[:pagy].next
    assert_nil first_page[:pagy].previous
    assert_equal 1, last_page[:legacy_logs].size
    assert_nil last_page[:pagy].next
    assert_equal 1, last_page[:pagy].previous
  end

  test "estimates the total from the ids when nothing filters, and counts otherwise" do
    first = create_legacy_log(person: @actor)
    create_legacy_log(person: @subject)
    last = create_legacy_log(person: @actor)

    unfiltered = LegacyLog.find_for_query
    filtered = LegacyLog.find_for_query(person_id: @actor.id)

    assert_equal last.id - first.id + 1, unfiltered[:total]
    assert unfiltered[:approximate_total]
    assert_equal 2, filtered[:total]
    assert_not filtered[:approximate_total]
  end

  test "a page past the total fetches nothing" do
    create_legacy_log

    result = LegacyLog.find_for_query(page: 3)

    assert_empty result[:legacy_logs]
    assert_equal 2, result[:pagy].previous
  end
end
