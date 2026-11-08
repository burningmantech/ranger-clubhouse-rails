# frozen_string_literal: true

require "test_helper"

# The Live mode's feed for Action Logs: who may listen, that a tick sends the
# new rows, page visits among them, as a turbo-stream of the shared rows
# partial, and what this feed adds to the Request Log's: audit rows that commit
# late behind a stream of page visits, a flood through its own partial, and a
# read of only the columns a row shows. The rest of LiveLogChannel is tested
# once, in RequestLogLiveChannelTest.
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

  test "a tick prepends the new rows, page visits among them, newest first" do
    assert listens?(@admin)
    first = record("auth-login", person: @actor)
    visit = record("page-visit", person: @actor, message: "me/dashboard")
    second = record("person-update", person: @actor, target_person: @target)

    subscription.send(:push)

    assert_equal 1, transmissions.size
    html = transmissions.last
    assert_match 'action="prepend"', html
    assert_match 'target="action-log-live-rows"', html
    assert_equal [second, visit, first].map { |row| row_id(row.id) }, row_ids(html)
    assert_match @actor.callsign, html
    assert_match @target.callsign, html
  end

  # An audit row's id is handed out inside its caller's transaction, while
  # every request's page visit commits at once: more of them than the page
  # opens with go out before the audit row commits.
  test "an audit row that commits behind more page visits than LOOKBACK still arrives" do
    shown = record("auth-login", person: @actor)
    late = record("person-update", person: @actor)
    late.delete
    assert listens?(@admin, since: shown.id.to_s)
    3.times do
      page_visits(60)
      subscription.send(:push)
    end

    record("person-update", person: @actor, id: late.id)
    subscription.send(:push)

    assert_equal 4, transmissions.size
    assert_equal [row_id(late.id)], row_ids(transmissions.last)
  end

  test "more waiting than one tick carries replaces the list with the newest rows" do
    assert listens?(@admin)
    limit = LiveLogChannel::BATCH_LIMIT
    events = %w[page-visit auth-login]
    ActionLog.insert_all(Array.new(limit + 1) { |n| { event: events[n % 2], message: "entry #{n}" } })

    subscription.send(:push)

    html = transmissions.last
    assert_match 'action="update"', html
    assert_match 'target="action-log-live-rows"', html
    assert_equal limit, row_ids(html).size
    assert_no_match row_id(ActionLog.minimum(:id)), html
  end

  test "the feed reads only what a Live row shows" do
    record("page-visit", message: "me/dashboard", ip: "10.0.0.1", user_agent: "Mozilla/5.0")

    row = ActionLogLiveChannel.feed.newest_first.first

    assert_equal "me/dashboard", row.message
    assert_not row.has_attribute?(:user_agent)
    assert_not row.has_attribute?(:data)
  end

  private

  def listens?(person, since: nil, gaps: nil)
    stub_connection current_user: person
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name("action-log"), since:, gaps:)
    subscription.confirmed?
  end

  def record(event, message: "", **attributes)
    ActionLog.create!(event:, message:, **attributes)
  end

  def page_visits(count)
    ActionLog.insert_all(Array.new(count) { { event: "page-visit", message: "me/dashboard" } })
  end

  def row_id(id) = %(id="action-log-live-#{id}")

  def row_ids(html) = html.scan(/id="action-log-live-\d+"/)
end
