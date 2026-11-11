# frozen_string_literal: true

require "test_helper"

class Person::SchedulingHelperTest < ActionView::TestCase
  # An override ScheduleLog reports with no badge here would raise on the page.
  test "every override ScheduleLog reports has a badge and a meaning" do
    assert_equal ScheduleLog::OVERRIDE_FLAGS.values.uniq.sort,
                 Person::SchedulingHelper::SCHEDULE_LOG_OVERRIDES.keys.sort
  end

  test "a removal reason reads in the page's words" do
    assert_equal "Shift deleted", schedule_log_reason("slot deletion")
    assert_equal "Position revoked", schedule_log_reason("position revoked")
  end
end
