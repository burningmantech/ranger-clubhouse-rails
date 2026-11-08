# frozen_string_literal: true

# The Live mode of an admin log page: Admin › Request Log and Admin › Action
# Logs. Nothing broadcasts a row as it is recorded: that would cost every
# write a partial render and a Solid Cable row whether or not anyone is
# watching. Instead each subscription asks the table every couple of seconds
# for the rows it has not sent yet, and transmits them as a turbo-stream. The
# cost is a primary-key read per watcher per tick (two while ids passed over
# are looked for), and nothing at all with no watcher; a hidden tab drops its
# subscription (live_log_controller.js), so it costs nothing either.
#
# A subclass says who may listen (authorized_roles), which table it reads
# (self.feed, which also gives the page the rows it opens with:
# opening_rows) and which turbo_stream partial it transmits (update_partial).
# The gate is asked again on every subscribe: a <turbo-cable-stream-source>
# left on a page outlives the role that opened it (MailboxStreamsChannel has
# the same reasoning).
class LiveLogChannel < ActionCable::Channel::Base
  INTERVAL = 2.seconds

  # The most one tick sends. More than this waiting is a flood, or the first
  # tick after a long gap, and the list is replaced by the newest rows rather
  # than topped up with a slice that would leave a hole beneath it.
  BATCH_LIMIT = 100

  # How many rows the page opens with. It names the newest of them and the ids
  # missing among them (data-since, data-gaps), so a new subscription starts
  # where the page stands.
  LOOKBACK = 100

  # A row is seen only once it commits, and Action Log rows are written inside
  # their callers' transactions: a bulk conversion's, or an account creation's
  # while it waits on Salesforce. So a tick can pass over an id while newer
  # rows go out, and that row commit later. Every id passed over is looked for
  # again on each tick for this long, however many rows arrive meanwhile; a
  # row whose transaction outlasts it never arrives, and the Search mode has it.
  GAP_HORIZON = 5.minutes

  # The most passed-over ids one subscription looks for, the newest kept: a
  # rolled-back change leaves its ids unused for good.
  MAX_GAPS = 1_000

  periodically :push, every: INTERVAL

  # The table a tick reads. It must answer newest_first: ordered by id
  # descending, and carrying the includes the rows partial needs.
  def self.feed = raise NotImplementedError

  # The rows the page opens with: the same read a tick makes, so the two agree.
  def self.opening_rows = feed.newest_first.limit(LOOKBACK).to_a

  private

  # Private, as Base's own is: a public one would be an action a client could
  # call on its subscription, resetting the cursor and the lock mid-tick.
  def subscribed
    return reject unless allowed?

    # The newest row the page holds, and the ids below it that it is missing:
    # only ids, and only below the newest, since the client says so.
    @cursor = IdList.id(params[:since])
    @gaps = {}
    note_gaps(IdList.parse(params[:gaps].to_s.split(",")).select { |id| id < @cursor }) if @cursor
    @push_lock = Mutex.new
  end

  # The roles that may listen: the page's own list, so the two never drift.
  # None here, so this class on its own refuses everyone: a client may
  # subscribe to any channel class by name.
  def authorized_roles = []

  # The turbo_stream partial transmitted, taking the locals rows: and action:.
  def update_partial = raise NotImplementedError

  def feed = self.class.feed

  # The page's roles, on an account that is not locked. A suspension keeps the
  # roles, and a Live tab makes no page request to end its session
  # (Authentication#end_locked_session), so the account is read again here.
  def allowed? = roles.has_role?(authorized_roles) && !Person.locked.exists?(id: current_user.id)

  # The timer only queues a tick, every INTERVAL, however long the last one
  # took. One still running when the next comes due makes that one skip: two
  # at once would read from the same cursor, and the slower finishing last
  # would put its older rows above the newer ones.
  def push
    return unless @push_lock.try_lock

    begin
      send_unsent_rows
    ensure
      @push_lock.unlock
    end
  end

  def send_unsent_rows
    expire_gaps
    fresh = fresh_rows
    late = late_rows
    return if fresh.empty? && late.empty?

    # Asked again before anything goes out: an account locked since the page
    # loaded is sent no more rows.
    return close_for_good unless allowed?

    if fresh.size + late.size > BATCH_LIMIT
      # Rows above the cursor are newer than any the page holds, so when they
      # alone are too many, the first of them are the newest in the table.
      rows = fresh.size > BATCH_LIMIT ? fresh.first(BATCH_LIMIT) : feed.newest_first.limit(BATCH_LIMIT).to_a
      transmit(render_update(rows, :update))
      start_again_at(rows)
    else
      # The late rows after the new ones: live_log_controller.js moves each to
      # its place among the rows the page holds.
      transmit(render_update(fresh + late, :prepend))
      advance_past(fresh, late)
    end
  end

  # Every row above the cursor, newest first: one more than a tick carries, so
  # a flood shows.
  def fresh_rows
    rows = @cursor ? feed.where(id: (@cursor + 1)..) : feed
    rows.newest_first.limit(BATCH_LIMIT + 1).to_a
  end

  # The rows that have turned up under ids passed over, newest first: one more
  # than a tick carries, so a burst of them shows.
  def late_rows
    return [] if @gaps.empty?

    feed.where(id: @gaps.keys).newest_first.limit(BATCH_LIMIT + 1).to_a
  end

  # Only once they are on their way: a tick whose render fails leaves its rows
  # for the next one instead of skipping past them. With nothing shown yet, the
  # ids LOOKBACK below the newest are watched, as if the page had opened on them.
  def advance_past(fresh, late)
    late.each { |row| @gaps.delete(row.id) }
    return if fresh.empty?

    ids = fresh.map(&:id)
    note_gaps(passed_over(@cursor || ids.first - LOOKBACK, ids))
    @cursor = ids.first
  end

  # The list starts again from these rows, so an id passed over below them is
  # looked for no more: nothing older than the list is.
  def start_again_at(rows)
    ids = rows.map(&:id)
    @gaps.clear
    note_gaps(passed_over(ids.last, ids))
    @cursor = ids.first
  end

  # The ids above floor and below the newest of ids that ids does not hold, at
  # most MAX_GAPS of them: a jump in the ids is not that many rows in flight.
  def passed_over(floor, ids)
    low = [floor, ids.first - MAX_GAPS - ids.size, 0].max
    ((low + 1)...ids.first).to_a - ids
  end

  def note_gaps(ids)
    now = clock
    ids.each { |id| @gaps[id] ||= now }
    @gaps = @gaps.max_by(MAX_GAPS) { |id, _| id }.to_h if @gaps.size > MAX_GAPS
  end

  def expire_gaps
    oldest = clock - GAP_HORIZON.to_i
    @gaps.delete_if { |_, noted| noted < oldest }
  end

  # Seconds on a clock that only runs forward, unlike the wall clock.
  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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
