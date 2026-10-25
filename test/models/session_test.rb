# frozen_string_literal: true

require "test_helper"

# A session that ends closes its person's cable connections: a socket is
# identified once, when it opens, so without this a tab left on a live page
# would go on receiving after a sign-out or a revoke.
class SessionTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "ending a session tells its person's cable connections to reconnect" do
    person = person(:active_ranger)
    session = person.sessions.create!(session_id: SecureRandom.hex(32))

    assert_broadcast_on("action_cable/#{person.to_gid_param}", { type: "disconnect", reconnect: true }) do
      session.destroy
    end
  end
end
