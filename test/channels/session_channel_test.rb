# frozen_string_literal: true

require "test_helper"

# A signed-in page subscribes with the sign-in it was drawn under
# (session_watch_controller.js); the channel answers whether its socket still
# belongs to that sign-in.
class SessionChannelTest < ActionCable::Channel::TestCase
  setup do
    @person = person(:active_ranger)
    @session = @person.sessions.create!(session_id: SecureRandom.hex(32))
    stub_connection current_user: @person, current_session: @session
    closes = @closes = []
    connection.define_singleton_method(:close) { |**options| closes << options }
  end

  test "confirms a page drawn under the socket's own sign-in" do
    subscribe session: @session.id

    assert subscription.confirmed?
    assert_empty @closes
  end

  test "rejects a page drawn under a sign-in the browser has since replaced" do
    earlier = @person.sessions.create!(session_id: SecureRandom.hex(32))
    earlier.destroy

    subscribe session: earlier.id

    assert subscription.rejected?
    assert_empty @closes
  end

  # The socket's sign-in ended while the page was being drawn for a newer one:
  # a fresh socket comes up under the cookie that newer sign-in left.
  test "reopens a socket that outlived its sign-in" do
    newer = @person.sessions.create!(session_id: SecureRandom.hex(32))
    @session.destroy

    subscribe session: newer.id

    assert_equal [{ reconnect: true }], @closes
    assert_not subscription.rejected?
  end
end
