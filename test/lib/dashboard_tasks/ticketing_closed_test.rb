# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::TicketingClosedTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  # An access document fake responding to the predicates TicketHelper.build_tickets calls.
  def access_doc(using: false, regular: false, banked: false, qualified: false, type: "gift")
    OpenStruct.new(
      is_using?: using,
      regular_ticket?: regular,
      is_banked?: banked,
      is_qualified?: qualified,
      type:
    )
  end

  # A ticketing_package fake matching the surface TicketHelper.build_tickets reads.
  def package(access_documents: [], gift_items: [], lsd_items: [],
              provisions_banked: false, provision_records: [],
              started_at: nil, finished_at: nil)
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

  test "ticketing period not closed is skipped" do
    result = DashboardTasks::TicketingClosed.check(
      facts(ticketing_period: "open", ticketing_package: package)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "nil ticketing package is skipped even when period closed" do
    result = DashboardTasks::TicketingClosed.check(
      facts(ticketing_period: "closed", ticketing_package: nil)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "closed period with package is completed with tickets and ticketing_open false" do
    pkg = package(
      access_documents: [
        access_doc(using: true, regular: true),          # claimed
        access_doc(banked: true),                        # banked_count
        access_doc(qualified: true, regular: true),      # qualified_count
        access_doc(qualified: true, type: AccessDocument::SAP) # not_critical_count
      ],
      gift_items: [access_doc(using: true)],
      lsd_items: [access_doc(using: true)],
      provisions_banked: false,
      provision_records: [:p1, :p2],
      started_at: Time.utc(2026, 6, 1),
      finished_at: nil
    )

    result = DashboardTasks::TicketingClosed.check(
      facts(ticketing_period: "closed", ticketing_package: pkg)
    )

    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "dashboard_tickets", result.partial
    assert_equal false, result.payload.ticketing_open

    tickets = result.payload.tickets
    # 1 claimed access doc + 1 gift + 1 lsd = 3 claimed
    assert_equal 3, tickets.claimed.length
    assert_equal 1, tickets.banked_count
    assert_equal 1, tickets.qualified_count
    assert_equal 1, tickets.not_critical_count
    assert_equal [:p1, :p2], tickets.provision_items
    assert tickets.not_finished
  end

  test "title metadata" do
    assert_equal "Ticketing Has Closed", DashboardTasks::TicketingClosed.title
  end

  test "period metadata" do
    assert_equal [DashboardTask::BEFORE_EVENT], DashboardTasks::TicketingClosed.period
  end
end
