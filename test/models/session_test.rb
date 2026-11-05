# frozen_string_literal: true

require "test_helper"

# A session that ends closes its own cable connections for good: a socket is
# identified once, when it opens, so without this a tab left on a live page
# would go on receiving after a sign-out or a revoke.
class SessionTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "ending a session closes its own cable connections for good and has the person's others reconnect" do
    person = person(:active_ranger)
    session = person.sessions.create!(session_id: SecureRandom.hex(32))
    other = person.sessions.create!(session_id: SecureRandom.hex(32))

    assert_broadcast_on(sockets_of(other), { type: "disconnect", reconnect: true }) do
      assert_broadcast_on(sockets_of(session), { type: "disconnect", reconnect: false }) do
        session.destroy
      end
    end
  end

  test "a signed session id finds its sign-in, and no cookie finds none" do
    session = person(:active_ranger).sessions.create!(session_id: SecureRandom.hex(32))

    assert_equal session, Session.signed_in(session.session_id)
    assert_nil Session.signed_in(nil)
  end

  private

  # Where Action Cable sends one connection's internal messages: the global ids
  # of its identifiers, sorted and joined (ActionCable::Connection::Identification).
  def sockets_of(session) = "action_cable/#{[session.person, session].map(&:to_gid_param).sort.join(":")}"
end
