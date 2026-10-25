class Session < ApplicationRecord
  belongs_to :person

  # A cable connection is identified once, when its socket opens, and nothing
  # reads the session again after that: a tab left open on a live page would
  # go on receiving under a session that has ended -- signed out, revoked at
  # Person › Login Sessions, or ended for a locked account. Closing the
  # person's connections makes each one reconnect, which a device whose own
  # session still stands does at once and a browser without one is refused.
  after_destroy_commit -> { ActionCable.server.remote_connections.where(current_user: person).disconnect }
end
