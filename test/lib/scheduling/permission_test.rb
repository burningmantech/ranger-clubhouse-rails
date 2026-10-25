# frozen_string_literal: true

require "test_helper"

class Scheduling::PermissionTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
  end

  test "a past prospective is blocked from all signups and reports the requirement" do
    permission = Scheduling::Permission.new(person(:past_prospective_ranger), Current.year)

    assert_not permission.all_signups_allowed
    assert_not permission.training_signups_allowed
    assert_includes permission.requirements, Scheduling::IS_PAST_PROSPECTIVE
  end
end
