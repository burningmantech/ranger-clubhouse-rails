# frozen_string_literal: true

require "test_helper"

# config/recurring.yml: which deployments run which scheduled tasks, and that
# every task it names can be scheduled. Solid Queue checks the list only when a
# server boots, and only the Production deployment gets the full list, so a
# typo there would otherwise first show as a failed production deploy.
class RecurringScheduleTest < ActiveSupport::TestCase
  include RecurringScheduleTestHelper

  HOUSEKEEPING = %w[clear_solid_queue_finished_jobs].freeze

  test "only the Production deployment runs the tasks that reach members" do
    assert_includes tasks(environment: "Production").keys, "daily_report"
    [nil, "Staging"].each { |label| assert_equal HOUSEKEEPING, tasks(environment: label).keys, label.inspect }
    # The training server reloads its copy instead, whatever its label says.
    assert_equal HOUSEKEEPING + %w[reload_training_database],
                 tasks(environment: "Production", ghd: "2026-08-25 12:00").keys
  end

  test "every Production task names a job that exists and a schedule the queue reads" do
    tasks(environment: "Production").each do |key, options|
      task = SolidQueue::RecurringTask.from_configuration(key, **options.symbolize_keys)
      assert_predicate task, :valid?, "#{key}: #{task.errors.full_messages.join(', ')}"
    end
  end

  private

  def tasks(**deployment)
    recurring_schedule(**deployment).fetch("production")
  end
end
