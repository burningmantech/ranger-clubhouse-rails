# frozen_string_literal: true

require "test_helper"

class LegacyLogTest < ActiveSupport::TestCase
  setup do
    LegacyLog.delete_all
    @actor = person(:active_ranger)
    @subject = person(:auditor_ranger)
  end

  def legacy(event: "unknown", message: event, person: nil, target: nil,
             created_at: Time.zone.parse("2015-06-01 12:00:00"), data: {})
    log_id = (LegacyLog.maximum(:log_id) || 0) + 1
    LegacyLog.insert!({ log_id:, person_id: person&.id, target_person_id: target&.id, event:, message:, data:,
                        created_at: })
    LegacyLog.find_by!(log_id:)
  end

  def ids(result)
    result[:legacy_logs].map(&:id)
  end

  test "nothing may be written through a record" do
    row = legacy

    assert_predicate row, :readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { row.update!(event: "changed") }
  end

  test "data is kept as JSON" do
    row = legacy(data: { "event" => "=person.status=alpha@id=1", "log_id" => 1, "target_source" => "session" })

    assert_equal({ "event" => "=person.status=alpha@id=1", "log_id" => 1, "target_source" => "session" }, row.data)
  end

  test "narrows to who acted, and to who was acted upon" do
    mine = legacy(person: @actor, target: @subject)
    theirs = legacy(person: @subject, target: @actor)

    assert_equal [mine.id], ids(LegacyLog.find_for_query(person_id: @actor.id))
    assert_equal [theirs.id], ids(LegacyLog.find_for_query(target_person_id: @actor.id))
    assert_equal [mine.id], ids(LegacyLog.find_for_query(person_id: @actor.id, target_person_id: @subject.id))
  end

  test "narrows to a time range" do
    inside = legacy(created_at: Time.zone.parse("2015-06-01 12:00:00"))
    legacy(created_at: Time.zone.parse("2014-01-01 12:00:00"))
    legacy(created_at: Time.zone.parse("2016-01-01 12:00:00"))

    result = LegacyLog.find_for_query(start_time: Time.zone.parse("2015-01-01 00:00:00"),
                                      end_time: Time.zone.parse("2015-12-31 23:59:59"))

    assert_equal [inside.id], ids(result)
  end

  test "matches an exact event name, a pattern, or either" do
    update = legacy(event: "person-update")
    add = legacy(event: "person-slot-add")
    legacy(event: "unknown")

    assert_equal [update.id], ids(LegacyLog.find_for_query(events: ["person-update"]))
    assert_equal [add.id], ids(LegacyLog.find_for_query(events: ["person-slot-%"]))
    assert_equal [add.id, update.id].sort, ids(LegacyLog.find_for_query(events: ["person-update", "person-slot-%"])).sort
  end

  test "matches a message exactly, or by pattern" do
    alpha = legacy(message: "=person.status=alpha@id=1")
    legacy(message: "=person.status=active@id=1")

    assert_equal [alpha.id], ids(LegacyLog.find_for_query(message: "=person.status=alpha@id=1"))
    assert_equal [alpha.id], ids(LegacyLog.find_for_query(message: "%alpha%"))
  end

  test "sorts newest first, the id breaking ties" do
    same_second = Time.zone.parse("2015-06-01 12:00:00")
    older = legacy(created_at: Time.zone.parse("2010-01-01 12:00:00"))
    first = legacy(created_at: same_second)
    second = legacy(created_at: same_second)

    assert_equal [second.id, first.id, older.id], ids(LegacyLog.find_for_query)
  end

  test "a full page says another follows, and the last page says none" do
    3.times { legacy }

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
    first = legacy(person: @actor)
    legacy(person: @subject)
    last = legacy(person: @actor)

    unfiltered = LegacyLog.find_for_query
    filtered = LegacyLog.find_for_query(person_id: @actor.id)

    assert_equal last.id - first.id + 1, unfiltered[:total]
    assert unfiltered[:approximate_total]
    assert_equal 2, filtered[:total]
    assert_not filtered[:approximate_total]
  end
end
