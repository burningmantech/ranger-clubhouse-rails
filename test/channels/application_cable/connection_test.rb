# frozen_string_literal: true

require "test_helper"

module ApplicationCable
  # A socket belongs to whoever the signed session cookie names, as a page
  # request does (Authentication#find_session_by_cookie). Live notifications
  # are streamed per person, so this is what keeps one person's stream from
  # opening for anyone else.
  class ConnectionTest < ActionCable::Connection::TestCase
    setup do
      @person = person(:active_ranger)
      @session = @person.sessions.create!(session_id: SecureRandom.hex(32))
    end

    test "connects as the person whose session the signed cookie names" do
      cookies.signed[:session_id] = @session.session_id

      connect

      assert_equal @person, connection.current_user
    end

    test "rejects a socket with no session cookie" do
      assert_reject_connection { connect }
    end

    test "rejects a socket whose session has ended" do
      cookies.signed[:session_id] = @session.session_id
      @session.destroy

      assert_reject_connection { connect }
    end

    test "rejects a session id that was not signed by the app" do
      cookies[:session_id] = @session.session_id

      assert_reject_connection { connect }
    end
  end
end
