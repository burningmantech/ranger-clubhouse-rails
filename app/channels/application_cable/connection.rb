module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      # As Authentication#find_session_by_cookie does: with no cookie there is
      # no lookup, since find_by(session_id: nil) would match a NULL id.
      def set_current_user
        session_id = cookies.signed[:session_id]
        self.current_user = Session.find_by(session_id:)&.person if session_id
      end
  end
end
