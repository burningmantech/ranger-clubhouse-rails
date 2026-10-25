# frozen_string_literal: true

# The Live mode of Admin › Request Log. Nothing broadcasts a request as it is
# recorded: that would cost every request a partial render and a Solid Cable
# row whether or not anyone is watching. Instead each subscription asks the
# table every couple of seconds for the rows it has not sent yet, and
# transmits them as a turbo-stream. The cost is one indexed query per watcher
# per tick, and nothing at all with no watcher; a hidden tab drops its
# subscription (live_log_controller.js), so it costs nothing either.
#
# The gate is the controller's own list, asked again on every subscribe: a
# <turbo-cable-stream-source> left on a page outlives the role that opened it
# (MailboxStreamsChannel has the same reasoning).
class RequestLogLiveChannel < ActionCable::Channel::Base
  INTERVAL = 2.seconds

  # The most one tick sends. More than this waiting is a flood, or the first
  # tick after a long gap, and the list is replaced by the newest rows rather
  # than topped up with a slice that would leave a hole beneath it.
  BATCH_LIMIT = 100

  # How far below the newest id sent each tick looks again. An id is handed
  # out when its row is inserted, and the row is seen only once it commits, so
  # two requests finishing together can commit out of order: the lower id
  # turns up after the higher one was sent. Ids already sent are skipped. The
  # page opens with this many rows, so a new subscription's window is the rows
  # the page shows, and it names them (data-shown) so none is sent twice.
  LOOKBACK = 100

  periodically :push, every: INTERVAL

  def subscribed
    return reject unless roles.has_role?(Admin::RequestLogsController.authorized_roles)

    @since = params[:since].to_i
    @sent = params[:shown].to_s.split(",").map(&:to_i).select { |id| in_window?(id) }.to_set
    @push_lock = Mutex.new
  end

  private

  # The timer only queues a tick, every INTERVAL, however long the last one
  # took. One still running when the next comes due makes that one skip: two
  # at once would read the same cursor, and the slower finishing last would
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
    rows = RequestLog.after_id(@since - LOOKBACK).where.not(id: @sent.to_a)
                     .newest_first.limit(BATCH_LIMIT + 1).to_a
    return if rows.empty?

    if rows.size > BATCH_LIMIT
      rows = RequestLog.newest_first.limit(BATCH_LIMIT).to_a
      transmit(render_update(rows, :update))
    else
      transmit(render_update(rows, :prepend))
    end

    # Only once they are on their way: a tick whose render fails leaves its
    # rows for the next one instead of skipping past them.
    remember_sent(rows)
  end

  def remember_sent(rows)
    @since = [@since, rows.first.id].max
    @sent.merge(rows.map(&:id))
    @sent.select! { |id| in_window?(id) }
  end

  def in_window?(id) = id > @since - LOOKBACK

  # The viewer's roles, read once: the gate is asked once per subscription
  # too, and a role lost mid-subscription takes effect when it next subscribes.
  def roles = @roles ||= RoleManager.retrieve(current_user)

  # The viewer's roles decide whether a callsign is a link, as they do on the
  # page: Current.has_role? answers false with no roles_manager.
  def render_update(rows, action)
    Current.set(person: current_user, roles_manager: roles) do
      Admin::RequestLogsController.render(partial: "admin/request_logs/live_update",
                                          formats: [:turbo_stream, :html], locals: { rows:, action: })
    end
  end
end
