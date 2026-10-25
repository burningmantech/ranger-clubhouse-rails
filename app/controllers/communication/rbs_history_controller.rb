# frozen_string_literal: true

# The record of every broadcast that has gone out: what it said, who it
# reached, and anything that failed to send.
class Communication::RbsHistoryController < ApplicationController
  layout "communication"

  authorize_role [Role::ADMIN, Role::TECH_NINJA],
                 message: "Admin or Tech Ninja role required to read the broadcast records."

  # admin: false -- reading the records is open to both roles, but sending a
  # broadcast's failed messages again is an Admin's call. The same gate answers
  # the Retry buttons in the view, so the button and the guard cannot disagree.
  authorize_ability :retry_broadcast,
                    only: [:retry],
                    roles: [Role::ADMIN],
                    admin: false,
                    deny_to: :communication_rbs_history_path,
                    message: "Only an Admin may send a broadcast's failed messages again."

  # The records begin in 2018; the pandemic years hold rows too, so no year in
  # range is skipped.
  self.year_floor = 2018

  # A year holds thousands of message alerts, and a page carrying all of them
  # is megabytes of table no one reads to the end. The list stops here and says
  # so; the filters above it are how a reader reaches the rest.
  LIST_LIMIT = 250

  before_action :setup_year, only: [:index]
  before_action :set_broadcast, only: [:show, :retry]
  before_action -> { prevent_if_ghd_server("Retrying a broadcast") }, only: [:retry]

  # Almost every row is the one-person alert sent when a Ranger receives a
  # Clubhouse message, so the list starts with the broadcasts someone sent to a
  # group and offers the rest behind the filter.
  def index
    @alerts = Alert.find_all.to_a
    @filters = filter_params
    matching = Broadcast.find_for_query(year: @year,
                                        kind: active_filter(:kind),
                                        failed: @filters[:delivery] == "failed",
                                        alert_id: active_filter(:alert_id))
    @matching_count = matching.count
    @broadcasts = matching.limit(LIST_LIMIT).to_a

    year_scope = Broadcast.all.where_year("broadcast.created_at", @year)
    @broadcast_count = year_scope.operator.count
    @notification_count = year_scope.notifications.count
    @failed_count = year_scope.with_failures.count
  end

  def show
    @recipients = @broadcast.recipients
  end

  # Sends only the messages that failed and may go again. Everyone who already
  # received the broadcast is left alone.
  def retry
    unless @broadcast.retryable?
      redirect_to communication_rbs_history_broadcast_path(@broadcast),
                  info: "Nothing in that broadcast can be sent again."
      return
    end

    @result = Rbs.retry_broadcast(@broadcast, current_user.id)
    @sandboxes, @email_test_address = RbsSandbox.notice

    render :retried, status: :unprocessable_entity
  end

  private

  def set_broadcast
    @broadcast = Broadcast.includes(:alert, :sender, :retry_person).find_by(id: params[:id])
    return if @broadcast

    redirect_to communication_rbs_history_path, error: "That broadcast could not be found."
  end

  # known_filter drops anything the page does not actually apply, so a stale
  # link cannot draw a chip claiming a filter that narrows nothing. A page
  # arriving with no kind at all starts on the broadcasts, since the message
  # alerts outnumber them by hundreds to one.
  def filter_params
    kind = params[:kind].presence || Broadcast::KIND_BROADCAST

    { kind: UiComponents::FilterBarHelper.known_filter(kind, Broadcast::KINDS),
      delivery: UiComponents::FilterBarHelper.known_filter(params[:delivery], %w[failed]),
      alert_id: UiComponents::FilterBarHelper.known_filter(params[:alert_id],
                                                          @alerts.map { |alert| alert.id.to_s }) }
  end

  def active_filter(key)
    value = @filters[key]
    value == UiComponents::FilterBarHelper::ALL_FILTER ? nil : value
  end
end
