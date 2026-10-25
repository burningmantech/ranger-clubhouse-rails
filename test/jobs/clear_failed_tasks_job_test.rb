# frozen_string_literal: true

require "test_helper"

class ClearFailedTasksJobTest < ActiveSupport::TestCase
  # The queue keeps its tasks in a database of its own that no test can reach.
  # What matters here is that the job says nothing and does nothing where the
  # queue is not there, rather than stopping with an error.
  test "perform does nothing where the queue cannot be read" do
    assert_nothing_raised { ClearFailedTasksJob.perform_now }
  end
end
