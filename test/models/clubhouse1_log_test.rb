# frozen_string_literal: true

require "test_helper"

class Clubhouse1LogTest < ActiveSupport::TestCase
  setup do
    Clubhouse1Log.delete_all
    @actor = person(:active_ranger)
    @subject = person(:auditor_ranger)
  end

  def create_log(event:, occurred: Time.zone.parse("2015-06-01 12:00:00"), user_person: nil, current_person: nil)
    Clubhouse1Log.insert!({
                            event:,
                            occurred:,
                            user_person_id: user_person&.id,
                            current_person_id: current_person&.id
                          })
    Clubhouse1Log.order(id: :desc).first
  end

  test "nothing may be written through a record" do
    row = create_log(event: "#login rangers")

    assert_predicate row, :readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { row.update!(event: "changed") }
  end

  test "returns every entry when nothing is asked of it" do
    create_log(event: "#login rangers")
    create_log(event: "!DB 'SQL error'")

    assert_equal 2, Clubhouse1Log.find_for_query[:logs].size
  end

  test "narrows to who acted" do
    mine = create_log(event: "#login rangers", user_person: @actor)
    create_log(event: "#login rangers", user_person: @subject)

    result = Clubhouse1Log.find_for_query(user_person_id: @actor.id)

    assert_equal [mine.id], result[:logs].map(&:id)
  end

  test "narrows to who was acted upon" do
    mine = create_log(event: "=person.status", current_person: @subject)
    create_log(event: "=person.status", current_person: @actor)

    result = Clubhouse1Log.find_for_query(current_person_id: @subject.id)

    assert_equal [mine.id], result[:logs].map(&:id)
  end

  test "the two person filters narrow together rather than either one matching" do
    both = create_log(event: "=person.status", user_person: @actor, current_person: @subject)
    create_log(event: "=person.status", user_person: @subject, current_person: @actor)

    result = Clubhouse1Log.find_for_query(user_person_id: @actor.id, current_person_id: @subject.id)

    assert_equal [both.id], result[:logs].map(&:id)
  end

  test "narrows to a time range" do
    inside = create_log(event: "#login rangers", occurred: Time.zone.parse("2015-06-01 12:00:00"))
    create_log(event: "#login rangers", occurred: Time.zone.parse("2014-01-01 12:00:00"))
    create_log(event: "#login rangers", occurred: Time.zone.parse("2016-01-01 12:00:00"))

    result = Clubhouse1Log.find_for_query(start_time: Time.zone.parse("2015-01-01 00:00:00"),
                                          end_time: Time.zone.parse("2015-12-31 23:59:59"))

    assert_equal [inside.id], result[:logs].map(&:id)
  end

  test "matches an entry beginning with any of the given openings" do
    login = create_log(event: "#login rangers")
    logout = create_log(event: "#logout rangers")
    create_log(event: "!DB 'SQL error'")

    result = Clubhouse1Log.find_for_query(event_prefixes: ["#login", "#logout"])

    assert_equal [login.id, logout.id].sort, result[:logs].map(&:id).sort
  end

  test "an opening matches only at the start of an entry" do
    create_log(event: "#REQ GET dashboard about #login")

    assert_empty Clubhouse1Log.find_for_query(event_prefixes: ["#login"])[:logs]
  end

  test "an underscore in an opening matches only an underscore" do
    real = create_log(event: "!EDBM_E_ERROR 'Salesforce failed'")
    create_log(event: "!EDBMxExERROR 'not the same thing'")

    result = Clubhouse1Log.find_for_query(event_prefixes: ["!EDBM_E_ERROR"])

    assert_equal [real.id], result[:logs].map(&:id)
  end

  test "matches text anywhere in an entry" do
    found = create_log(event: "#REQ GET timesheet:selectByCallsign")
    create_log(event: "#REQ GET dashboard:mypersonalinfo")

    result = Clubhouse1Log.find_for_query(event_text: "timesheet")

    assert_equal [found.id], result[:logs].map(&:id)
  end

  test "a percent sign in the search text is looked for, not treated as a wildcard" do
    literal = create_log(event: "#credit gave 100% of the hours")
    create_log(event: "#credit gave some of the hours")

    result = Clubhouse1Log.find_for_query(event_text: "100%")

    assert_equal [literal.id], result[:logs].map(&:id)
  end

  test "sorts newest first by default and oldest first on request" do
    older = create_log(event: "#login rangers", occurred: Time.zone.parse("2010-01-01 12:00:00"))
    newer = create_log(event: "#login rangers", occurred: Time.zone.parse("2018-01-01 12:00:00"))

    assert_equal [newer.id, older.id], Clubhouse1Log.find_for_query[:logs].map(&:id)
    assert_equal [older.id, newer.id], Clubhouse1Log.find_for_query(sort: "asc")[:logs].map(&:id)
  end

  test "entries stamped the same second still hold a settled order" do
    same_second = Time.zone.parse("2015-06-01 12:00:00")
    first = create_log(event: "#login one", occurred: same_second)
    second = create_log(event: "#login two", occurred: same_second)

    assert_equal [second.id, first.id], Clubhouse1Log.find_for_query[:logs].map(&:id)
  end

  test "a full page reports that another page follows" do
    3.times { |n| create_log(event: "#login #{n}") }

    result = Clubhouse1Log.find_for_query(page_size: 2)

    assert_equal 2, result[:logs].size
    assert result[:meta][:has_next_page]
    assert_not result[:meta][:has_previous_page]
  end

  test "the last page reports no page after it" do
    3.times { |n| create_log(event: "#login #{n}") }

    result = Clubhouse1Log.find_for_query(page: 2, page_size: 2)

    assert_equal 1, result[:logs].size
    assert_not result[:meta][:has_next_page]
    assert result[:meta][:has_previous_page]
  end

  test "a page holding exactly the page size reports no page after it" do
    2.times { |n| create_log(event: "#login #{n}") }

    result = Clubhouse1Log.find_for_query(page_size: 2)

    assert_equal 2, result[:logs].size
    assert_not result[:meta][:has_next_page]
  end

  test "a page number below one is read as the first page" do
    create_log(event: "#login rangers")

    result = Clubhouse1Log.find_for_query(page: 0)

    assert_equal 1, result[:meta][:page]
    assert_equal 1, result[:logs].size
  end
end
