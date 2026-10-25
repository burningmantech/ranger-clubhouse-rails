# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::TicketingOpenTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  # An access document fake responding to every predicate TicketHelper.build_tickets reads.
  def access_doc(using: false, regular: false, banked: false, qualified: false, type: nil)
    OpenStruct.new(
      is_using?: using,
      regular_ticket?: regular,
      is_banked?: banked,
      is_qualified?: qualified,
      type:
    )
  end

  # A ticketing_package fake whose collections/predicates back build_tickets.
  def package(access_documents: [], gift_items: [], lsd_items: [], provisions_banked: true,
              provision_records: [], started_at: nil, finished_at: nil)
    OpenStruct.new(
      access_documents:,
      gift_items:,
      lsd_items:,
      provisions_banked:,
      provision_records:,
      started_at:,
      finished_at:
    )
  end

  test "skips when ticketing_period is not open" do
    result = DashboardTasks::TicketingOpen.check(facts(ticketing_period: "closed", ticketing_package: package))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when ticketing_period is nil" do
    result = DashboardTasks::TicketingOpen.check(facts(ticketing_period: nil, ticketing_package: package))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when ticketing_package is nil even if period is open" do
    result = DashboardTasks::TicketingOpen.check(facts(ticketing_period: "open", ticketing_package: nil))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "action needed when qualified_count > 0" do
    pkg = package(access_documents: [access_doc(qualified: true, regular: true)])
    result = DashboardTasks::TicketingOpen.check(facts(ticketing_period: "open", ticketing_package: pkg))

    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "dashboard_tickets", result.partial
    assert result.immediate
    assert_equal 1, result.payload.tickets.qualified_count
  end

  test "action needed when not_finished (started but not finished)" do
    pkg = package(started_at: Time.utc(2026, 6, 1), finished_at: nil)
    result = DashboardTasks::TicketingOpen.check(facts(ticketing_period: "open", ticketing_package: pkg))

    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "dashboard_tickets", result.partial
    assert result.immediate
    assert result.payload.tickets.not_finished
  end

  test "completed when nothing qualified and ticketing is finished" do
    pkg = package(
      access_documents: [access_doc(qualified: false, regular: true)],
      started_at: Time.utc(2026, 6, 1),
      finished_at: Time.utc(2026, 6, 2)
    )
    result = DashboardTasks::TicketingOpen.check(facts(ticketing_period: "open", ticketing_package: pkg))

    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "dashboard_tickets", result.partial
    assert result.payload.ticketing_open
    assert_equal 0, result.payload.tickets.qualified_count
    assert_not result.payload.tickets.not_finished
  end

  test "completed when ticketing never started (not_finished is falsey)" do
    pkg = package(access_documents: [], started_at: nil, finished_at: nil)
    result = DashboardTasks::TicketingOpen.check(facts(ticketing_period: "open", ticketing_package: pkg))

    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert result.payload.ticketing_open
  end

  test "skip_period excludes post-event and after-event" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::TicketingOpen.skip_period
  end

  test "title is set" do
    assert_equal "Claim Tickets, Vehicle Passes, and Setup Access Passes",
                 DashboardTasks::TicketingOpen.title
  end
end
