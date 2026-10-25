# frozen_string_literal: true

require "test_helper"

# The Live mode's feed: who may listen, that each tick sends the rows it has
# not sent yet as a turbo-stream of the shared rows partial, and the ways a
# tick can go wrong -- a row that commits late, a flood, a render that fails,
# a tick that overlaps the one before it.
class RequestLogLiveChannelTest < ActionCable::Channel::TestCase
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    RequestLog.delete_all
    @admin = person(:active_ranger)
    @tech_ninja = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "an Admin and a Tech Ninja may listen; no one else may" do
    assert listens?(@admin)
    assert listens?(@tech_ninja)
    assert_not listens?(@outsider)
  end

  test "each tick prepends what it has not sent yet, newest first" do
    assert listens?(@admin)
    subscription.send(:push)
    assert_empty transmissions

    first = record("me/schedule", person: @tech_ninja)
    second = record("admin/settings", status: 422, method: "POST")
    subscription.send(:push)

    assert_equal 1, transmissions.size
    html = transmissions.last
    assert_match 'action="prepend"', html
    assert_match 'target="request-log-live-rows"', html
    assert_operator html.index(row_id(second.id)), :<, html.index(row_id(first.id))
    assert_match @tech_ninja.callsign, html
    # The badge itself: a bare "422" would also match a row whose id holds it.
    assert_match(/#{Regexp.escape(row_id(second.id))}.*?<span class="badge[^"]*">422<\/span>/m, html)

    subscription.send(:push)
    assert_equal 1, transmissions.size
  end

  test "the first tick leaves out the rows the page already shows" do
    shown = record("me/dashboard")
    assert listens?(@admin, since: shown.id, shown: shown.id.to_s)

    subscription.send(:push)

    assert_empty transmissions
  end

  # An id handed out first and committed last: the row's id is freed, a newer
  # row is sent, and the row then turns up below it.
  test "a row that commits after a newer one was sent still arrives" do
    assert listens?(@admin)
    late = record("me/dashboard")
    newer = record("me/schedule")
    late.delete
    subscription.send(:push)
    assert_match row_id(newer.id), transmissions.last

    record("me/profile", id: late.id)
    subscription.send(:push)

    assert_equal 2, transmissions.size
    assert_match row_id(late.id), transmissions.last
    assert_no_match row_id(newer.id), transmissions.last
  end

  test "more waiting than one tick carries replaces the list with the newest rows" do
    assert listens?(@admin)
    limit = RequestLogLiveChannel::BATCH_LIMIT
    RequestLog.insert_all(Array.new(limit + 1) { |n| row_attributes("me/page-#{n}") })

    subscription.send(:push)

    html = transmissions.last
    assert_match 'action="update"', html
    assert_equal limit, html.scan('id="request-log-live-').size
    assert_no_match row_id(RequestLog.minimum(:id)), html
  end

  test "a tick whose render fails leaves its rows for the next one" do
    assert listens?(@admin)
    row = record("me/schedule")
    channel = subscription
    channel.define_singleton_method(:render_update) { |*| raise "rendering failed" }
    begin
      assert_raises(RuntimeError) { channel.send(:push) }
    ensure
      channel.singleton_class.remove_method(:render_update)
    end

    channel.send(:push)

    assert_match row_id(row.id), transmissions.last
  end

  test "a tick skips while the one before it is still running" do
    assert listens?(@admin)
    record("me/schedule")

    subscription.instance_variable_get(:@push_lock).synchronize { subscription.send(:push) }
    assert_empty transmissions

    subscription.send(:push)
    assert_equal 1, transmissions.size
  end

  private

  def listens?(person, since: 0, shown: nil)
    stub_connection current_user: person
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name("request-log"), since:, shown:)
    subscription.confirmed?
  end

  def record(url, **attributes)
    RequestLog.create!(row_attributes(url).merge(attributes))
  end

  def row_attributes(url)
    { ips: "10.0.0.1", url:, status: 200, method: "GET", response_size: 10, completion_time: 1.0 }
  end

  def row_id(id) = %(id="request-log-live-#{id}")
end
