# frozen_string_literal: true

# The Live mode of an admin log page: Admin › Request Log and Admin › Action
# Logs. Nothing broadcasts a row as it is recorded: that would cost every
# write a partial render and a Solid Cable row whether or not anyone is
# watching. Instead each subscription asks the table every couple of seconds
# for the rows it has not sent yet, and transmits them as a turbo-stream. The
# cost is one indexed query per watcher per tick, and nothing at all with no
# watcher; a hidden tab drops its subscription (live_log_controller.js), so it
# costs nothing either.
#
# A subclass says who may listen (authorized_roles), which scope a tick reads
# (feed) and which turbo_stream partial it transmits (update_partial). The
# gate is asked again on every subscribe: a <turbo-cable-stream-source> left
# on a page outlives the role that opened it (MailboxStreamsChannel has the
# same reasoning).
class LiveLogChannel < ActionCable::Channel::Base
  INTERVAL = 2.seconds

  # The most one tick sends. More than this waiting is a flood, or the first
  # tick after a long gap, and the list is replaced by the newest rows rather
  # than topped up with a slice that would leave a hole beneath it.
  BATCH_LIMIT = 100

  # How many of the newest rows sent each tick looks back over. A row is seen
  # only once it commits, so one inserted early can commit after a newer one
  # was sent: Action Log rows are written inside their callers' transactions,
  # a bulk conversion's among them, while every request takes another id for
  # its page visit. So the window reaches back to the oldest of the last
  # LOOKBACK rows sent, however many ids that spans, and never less than
  # LOOKBACK ids below the newest; the ids already sent are skipped. The page
  # opens with this many rows and names them (data-shown), so a new
  # subscription's window is the rows the page shows.
  LOOKBACK = 100

  periodically :push, every: INTERVAL

  private

  # Private, as Base's own is: a public one would be an action a client could
  # call on its subscription, resetting the window and the lock mid-tick.
  def subscribed
    return reject unless allowed?

    # The newest LOOKBACK of the ids the page names, and only ids: more would
    # only lengthen the NOT IN every tick sends.
    @sent = IdList.parse(params[:shown].to_s.split(",")).max(LOOKBACK).to_set
    @push_lock = Mutex.new
  end

  # The roles that may listen: the page's own list, so the two never drift.
  # None here, so this class on its own refuses everyone: a client may
  # subscribe to any channel class by name.
  def authorized_roles = []

  # The scope a tick reads. It must answer newest_first: ordered by id
  # descending, as the window is read from the first rows, and carrying the
  # includes the rows partial needs.
  def feed = raise NotImplementedError

  # The turbo_stream partial transmitted, taking the locals rows: and action:.
  def update_partial = raise NotImplementedError

  # The page's roles, on an account that is not locked. A suspension keeps the
  # roles, and a Live tab makes no page request to end its session
  # (Authentication#end_locked_session), so the account is read again here.
  def allowed? = roles.has_role?(authorized_roles) && !Person.locked.exists?(id: current_user.id)

  # The timer only queues a tick, every INTERVAL, however long the last one
  # took. One still running when the next comes due makes that one skip: two
  # at once would read the same window, and the slower finishing last would
  # put its older rows above the newer ones.
  def push
    return unless @push_lock.try_lock

    begin
      send_unsent_rows
    ensure
      @push_lock.unlock
    end
  end

  def send_unsent_rows
    rows = unsent_rows
    return if rows.empty?

    # Asked again before anything goes out: an account locked since the page
    # loaded is sent no more rows.
    return close_for_good unless allowed?

    if rows.size > BATCH_LIMIT
      rows = feed.newest_first.limit(BATCH_LIMIT).to_a
      transmit(render_update(rows, :update))
    else
      transmit(render_update(rows, :prepend))
    end

    # Only once they are on their way: a tick whose render fails leaves its
    # rows for the next one instead of skipping past them.
    remember_sent(rows)
  end

  # The window's rows not sent yet, newest first: one more than a tick
  # carries, so a flood shows.
  def unsent_rows
    start = window_start
    window = start ? feed.where(id: start..) : feed
    window.where.not(id: @sent.to_a).newest_first.limit(BATCH_LIMIT + 1).to_a
  end

  # The lowest id the window covers, or nil while nothing has been sent and
  # the page showed nothing. It only ever rises, so an id dropped from @sent
  # below it is never read again.
  def window_start
    newest = @sent.max(LOOKBACK)
    [newest.last, newest.first - LOOKBACK + 1].min if newest.any?
  end

  def remember_sent(rows)
    @sent.merge(rows.map(&:id))
    start = window_start
    @sent.select! { |id| id >= start }
  end

  # Closed for good rather than refused: session_watch_controller.js reloads
  # the page, and that request ends the locked account's session with the
  # locked-account message.
  def close_for_good
    connection.close(reason: ActionCable::INTERNAL[:disconnect_reasons][:unauthorized], reconnect: false)
  end

  # The viewer's roles, read once: the gate is asked once per subscription
  # too, and a role lost mid-subscription takes effect when it next subscribes.
  def roles = @roles ||= RoleManager.retrieve(current_user)

  # The viewer's roles decide whether a callsign is a link, as they do on the
  # page: Current.has_role? answers false with no roles_manager.
  def render_update(rows, action)
    Current.set(person: current_user, roles_manager: roles) do
      ApplicationController.render(partial: update_partial, formats: [:turbo_stream, :html],
                                   locals: { rows:, action: })
    end
  end
end
