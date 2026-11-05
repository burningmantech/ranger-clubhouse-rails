module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # The session as well as the person, so that ending one sign-in closes the
    # sockets of that sign-in alone (Session#close_cable_connections).
    identified_by :current_user, :current_session

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      # The sign-in a page request would find (Session.signed_in).
      def set_current_user
        self.current_session = Session.signed_in(cookies.signed[:session_id])
        self.current_user = current_session&.person
      end
  end
end
