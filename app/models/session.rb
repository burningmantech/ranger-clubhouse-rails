class Session < ApplicationRecord
  # The table is shared with the Rack session store (config.session_store
  # :active_record_store), whose rows carry no person and hold only the flash,
  # the CSRF token and the odd return-to address; the store touches a row on
  # every request. One idle this long is a visitor who left, and goes. A
  # sign-in row is never touched after it is written, so it is never swept:
  # the cookie is permanent by design and Person › Login Sessions ends one.
  ANONYMOUS_IDLE_DAYS = 30
  EXPIRE_BATCH_SIZE = 5_000

  belongs_to :person

  # A cable connection is identified once, when its socket opens, and nothing
  # reads the session again after that: a tab left open on a live page would
  # go on receiving under a session that has ended -- signed out, revoked at
  # Person › Login Sessions, or ended for a locked account. Closing the
  # person's connections makes each one reconnect, which a device whose own
  # session still stands does at once and a browser without one is refused.
  after_destroy_commit -> { ActionCable.server.remote_connections.where(current_user: person).disconnect }

  # Remove the Rack session store's rows nobody has used in a month.
  #
  # @return [Integer] how many rows were removed
  def self.expire_anonymous(days = ANONYMOUS_IDLE_DAYS)
    where(person_id: nil).where("updated_at < ?", days.days.ago)
                         .in_batches(of: EXPIRE_BATCH_SIZE)
                         .sum(&:delete_all)
  end
end
