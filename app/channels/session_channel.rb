# frozen_string_literal: true

# Streams nothing. A signed-in page subscribes with the sign-in it was drawn
# under (session_watch_controller.js), and learns that sign-in has ended when
# its socket is closed for good (Session#close_cable_connections) or this
# subscription is rejected.
class SessionChannel < ActionCable::Channel::Base
  def subscribed
    return if params[:session].to_i == current_session.id

    # The socket outlived the sign-in it opened under, which ended while this
    # page was being drawn for a newer one: a fresh socket picks up the cookie.
    return connection.close(reconnect: true) unless Session.exists?(current_session.id)

    # The page outlived its sign-in: the browser has signed in again since.
    reject
  end
end
