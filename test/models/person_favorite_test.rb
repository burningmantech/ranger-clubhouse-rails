# frozen_string_literal: true

require "test_helper"

class PersonFavoriteTest < ActiveSupport::TestCase
  test "toggle! creates then removes a favorite" do
    person = person(:active_ranger)

    assert_difference "PersonFavorite.count", 1 do
      assert PersonFavorite.toggle!(person.id, "/me/profile")
    end

    assert_difference "PersonFavorite.count", -1 do
      assert_not PersonFavorite.toggle!(person.id, "/me/profile")
    end
  end

  test "favorites are unique per person and path" do
    person = person(:active_ranger)
    PersonFavorite.create!(person_id: person.id, path: "/me/profile")

    assert_raises ActiveRecord::RecordNotUnique do
      PersonFavorite.create!(person_id: person.id, path: "/me/profile")
    end
  end
end
