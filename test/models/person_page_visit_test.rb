# frozen_string_literal: true

require "test_helper"

class PersonPageVisitTest < ActiveSupport::TestCase
  test "record creates a visit row" do
    person = person(:active_ranger)

    assert_difference "PersonPageVisit.count", 1 do
      PersonPageVisit.record(person.id, "/me/schedule")
    end
  end

  test "record bumps visited_at instead of duplicating" do
    person = person(:active_ranger)
    PersonPageVisit.record(person.id, "/me/schedule")
    visit = PersonPageVisit.find_by!(person_id: person.id, path: "/me/schedule")
    visit.update_columns(visited_at: 2.days.ago)

    assert_no_difference "PersonPageVisit.count" do
      PersonPageVisit.record(person.id, "/me/schedule")
    end

    assert visit.reload.visited_at > 1.day.ago
  end
end
