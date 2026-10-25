# frozen_string_literal: true

require "test_helper"

class RequestLogTest < ActiveSupport::TestCase
  BASE_TIME = Time.zone.parse("2026-08-01 10:00:00")

  setup do
    RequestLog.delete_all

    @person = person(:active_ranger)
    @other = person(:inactive_ranger)
  end

  def create_log(**attributes)
    RequestLog.create!({
      person: nil,
      ips: "10.0.0.1",
      url: "me/dashboard",
      status: 200,
      method: "GET",
      response_size: 100,
      completion_time: 1.5,
      created_at: BASE_TIME
    }.merge(attributes))
  end

  def found(**query)
    RequestLog.find_for_query(**query)[:request_log]
  end

  test "finds every record when nothing is asked for" do
    create_log
    create_log(person: @person)

    result = RequestLog.find_for_query

    assert_equal 2, result[:request_log].size
    assert_equal 2, result[:meta][:total]
    assert_equal 1, result[:meta][:total_pages]
    assert_equal 1, result[:meta][:page]
  end

  test "narrows to one person" do
    mine = create_log(person: @person)
    create_log(person: @other)

    assert_equal [mine.id], found(person_id: @person.id).map(&:id)
  end

  test "narrows to a status range" do
    rejected = create_log(status: 422)
    create_log(status: 200)
    create_log(status: 500)

    assert_equal [rejected.id], found(status_class: "4xx").map(&:id)
  end

  test "ignores a status range it does not offer" do
    create_log(status: 200)

    assert_equal 1, found(status_class: "9xx").size
  end

  test "narrows to a verb" do
    posted = create_log(method: "POST")
    create_log(method: "GET")

    assert_equal [posted.id], found(http_method: "POST").map(&:id)
  end

  test "narrows to a time range" do
    early = create_log(created_at: BASE_TIME - 2.hours)
    middle = create_log(created_at: BASE_TIME)
    late = create_log(created_at: BASE_TIME + 2.hours)

    ids = found(start_time: BASE_TIME - 1.hour, end_time: BASE_TIME + 1.hour).map(&:id)

    assert_equal [middle.id], ids
    assert_not_includes ids, early.id
    assert_not_includes ids, late.id
  end

  test "matches part of an address" do
    wanted = create_log(ips: "198.51.100.7")
    create_log(ips: "203.0.113.9")

    assert_equal [wanted.id], found(ip: "51.100").map(&:id)
  end

  test "returns newest first, breaking ties within a second by id" do
    first = create_log(created_at: BASE_TIME)
    second = create_log(created_at: BASE_TIME)
    older = create_log(created_at: BASE_TIME - 1.day)

    assert_equal [second.id, first.id, older.id], found.map(&:id)
  end

  test "holds a page number past the end to the last real page" do
    create_log

    meta = RequestLog.find_for_query(page: 99)[:meta]

    assert_equal 1, meta[:page]
  end

  test "reports no pages and no rows when nothing matches" do
    create_log(status: 200)

    result = RequestLog.find_for_query(status_class: "5xx")

    assert_empty result[:request_log]
    assert_equal 0, result[:meta][:total]
  end

  test "client_ip reads the last address of a forwarded chain" do
    log = create_log(ips: "203.0.113.9, 198.51.100.7")

    assert_equal "198.51.100.7", log.client_ip
  end

  test "record rounds the elapsed time and keeps payloads inside the limit" do
    RequestLog.record(
      person_id: @person.id,
      ips: "10.0.0.1",
      url: "me/dashboard",
      status: 422,
      method: "POST",
      response_size: 10,
      completion_time: 12.3456,
      request_payload: "x" * (RequestLog::PAYLOAD_LIMIT + 500),
      response_payload: nil
    )

    log = RequestLog.last

    assert_equal 12.35, log.completion_time
    assert_equal RequestLog::PAYLOAD_LIMIT, log.request_payload.bytesize
    assert_nil log.response_payload
  end

  test "expire removes only records past the window and reports the count" do
    old = create_log(created_at: 10.days.ago)
    recent = create_log(created_at: 1.day.ago)

    assert_equal 1, RequestLog.expire

    assert_not RequestLog.exists?(old.id)
    assert RequestLog.exists?(recent.id)
  end
end
