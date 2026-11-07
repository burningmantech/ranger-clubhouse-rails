# frozen_string_literal: true

require "test_helper"

# The Live mode's feed for Action Logs: who may listen, that a tick sends the
# new rows as a turbo-stream of the shared rows partial, that a page visit
# never goes, and what this feed has that the Request Log's does not: rows
# that commit late behind page visits, and a flood that must keep the filter.
# The rest of LiveLogChannel is tested once, in RequestLogLiveChannelTest.
class ActionLogLiveChannelTest < ActionCable::Channel::TestCase
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    @admin = person(:auditor_ranger)
    @tech_ninja = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @actor = person(:active_ranger)
    @target = person(:prospective_ranger)
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)
    # Creating a role logs a role-create row: start from an empty log.
    ActionLog.delete_all
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "an Admin may listen; a Tech Ninja and anyone else may not" do
    assert listens?(@admin)
    assert_not listens?(@tech_ninja)
    assert_not listens?(@outsider)
  end

  test "a locked Admin may not listen" do
    @admin.update_column(:status, Person::SUSPENDED)

    assert_not listens?(@admin)
  end

  test "an Admin locked while listening is sent nothing more, and the socket closes for good" do
    assert listens?(@admin)
    closed = []
    connection.define_singleton_method(:close) { |**options| closed << options }
    @admin.update_column(:status, Person::SUSPENDED)
    record("auth-login", person: @actor)

    subscription.send(:push)

    assert_empty transmissions
    assert_equal [false], closed.map { |options| options[:reconnect] }
  end

  test "a tick prepends the new rows, newest first, and never a page visit" do
    assert listens?(@admin)
    first = record("auth-login", person: @actor)
    visit = record("page-visit", person: @actor, message: "me/dashboard")
    second = record("person-update", person: @actor, target_person: @target)

    subscription.send(:push)

    assert_equal 1, transmissions.size
    html = transmissions.last
    assert_match 'action="prepend"', html
    assert_match 'target="action-log-live-rows"', html
    assert_operator html.index(row_id(second.id)), :<, html.index(row_id(first.id))
    assert_no_match row_id(visit.id), html
    assert_match @actor.callsign, html
    assert_match @target.callsign, html
  end

  # An id handed out early and committed late: a newer row is sent meanwhile,
  # with more than LOOKBACK page visits taking ids in between.
  test "a row that commits late, behind page visits, still arrives" do
    shown = record("auth-login", person: @actor)
    late = record("person-update", person: @actor)
    late.delete
    page_visits(LiveLogChannel::LOOKBACK + 50)
    assert listens?(@admin, shown: shown.id.to_s)
    newer = record("auth-login", person: @target)
    subscription.send(:push)
    assert_match row_id(newer.id), transmissions.last

    record("person-update", person: @actor, id: late.id)
    subscription.send(:push)

    assert_equal 2, transmissions.size
    assert_match row_id(late.id), transmissions.last
  end

  test "more waiting than one tick carries replaces the list with the newest rows, page visits left out" do
    assert listens?(@admin)
    limit = LiveLogChannel::BATCH_LIMIT
    ActionLog.insert_all(Array.new(limit + 1) { |n| { event: "auth-login", message: "entry #{n}" } })
    page_visits(5)

    subscription.send(:push)

    html = transmissions.last
    assert_match 'action="update"', html
    assert_equal limit, html.scan('id="action-log-live-').size
    ActionLog.where(event: "page-visit").pluck(:id).each { |id| assert_no_match row_id(id), html }
  end

  private

  def listens?(person, shown: nil)
    stub_connection current_user: person
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name("action-log"), shown:)
    subscription.confirmed?
  end

  def record(event, message: "", **attributes)
    ActionLog.create!(event:, message:, **attributes)
  end

  def page_visits(count)
    ActionLog.insert_all(Array.new(count) { { event: "page-visit", message: "me/dashboard" } })
  end

  def row_id(id) = %(id="action-log-live-#{id}")
end
