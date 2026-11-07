class Session < ApplicationRecord
  # The table is shared with the Rack session store (config.session_store
  # :active_record_store), whose rows carry no person and hold only the flash,
  # the CSRF token and the odd return-to address. The store saves a row only
  # when its data changed, so updated_at is the last change, not the last
  # visit: a row unchanged this long goes, and a reader who somehow never
  # changed theirs in that time gets a fresh session and a new CSRF token (one
  # form left open fails once). A sign-in row is never touched after it is
  # written, so it is never swept: the cookie is permanent by design and
  # Person › Login Sessions ends one.
  ANONYMOUS_IDLE_DAYS = 90
  EXPIRE_BATCH_SIZE = 5_000

  belongs_to :person

  truncates_to_column :user_agent, :ip_address

  after_destroy_commit :close_cable_connections

  # The sign-in a signed session_id cookie names, or nil with no cookie
  # (session_id is NOT NULL since 2026-10-29). Page requests
  # (Authentication#find_session_by_cookie) and cable connections both find a
  # sign-in here, so the cable never refuses one a page accepts.
  #
  # @param session_id [String, nil] cookies.signed[:session_id]
  # @return [Session, nil]
  def self.signed_in(session_id)
    find_by(session_id:) if session_id
  end

  # Remove the Rack session store's rows whose data has not changed in ANONYMOUS_IDLE_DAYS.
  #
  # @return [Integer] how many rows were removed
  def self.expire_anonymous(days = ANONYMOUS_IDLE_DAYS)
    where(person_id: nil).where("updated_at < ?", days.days.ago)
                         .in_batches(of: EXPIRE_BATCH_SIZE)
                         .sum(&:delete_all)
  end

  private

  # A cable connection is identified once, when its socket opens, and nothing
  # reads the session again after that, so a tab left on a live page would go on
  # receiving under a sign-in that has ended: signed out, revoked at Person ›
  # Login Sessions, or ended at a locked account's next request. This sign-in's
  # sockets, every window of its browser, close for good, and
  # session_watch_controller.js takes each page to the sign-in page. The
  # person's other sign-ins reconnect, which re-runs each channel's
  # subscribe-time gates there: a role removed before a revoke takes effect on
  # every device.
  def close_cable_connections
    connections = ActionCable.server.remote_connections
    connections.where(current_user: person, current_session: self).disconnect(reconnect: false)
    person.sessions.find_each { |other| connections.where(current_user: person, current_session: other).disconnect }
  end
end
