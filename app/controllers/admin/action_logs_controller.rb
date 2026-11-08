# frozen_string_literal: true

class Admin::ActionLogsController < ApplicationController
  layout "admin"

  authorize_role Role::ADMIN

  def index
    return live if params[:mode] == "live"

    @form = ActionLogFilterForm.new(filter_params)

    person_id = resolve_person_id(@form.person_callsign)
    target_person_id = resolve_person_id(@form.target_person_callsign)

    # A callsign no one has matches no row: the same query, with nothing to find.
    logs = if unknown_callsign?(@form.person_callsign, person_id) ||
              unknown_callsign?(@form.target_person_callsign, target_person_id)
             ActionLog.none
           else
             ActionLog
           end
    @result = logs.find_for_query(
      person_id: person_id.presence,
      target_person_id: target_person_id.presence,
      start_time: @form.parsed_start_time,
      end_time: @form.parsed_end_time,
      events: @form.events,
      message: @form.message.presence,
      page: @form.page
    )

    @action_logs = @result[:action_logs]
    @pagy = @result[:pagy]
  end

  private

  # The Live mode: the newest rows now, read as ActionLogLiveChannel reads
  # them, and the channel sends what arrives after them. Rendered from index
  # so the mode toggle is one page.
  def live
    @live_logs = ActionLogLiveChannel.opening_rows
    render :index
  end

  def filter_params
    scoped_params(ActionLogFilterForm::PARAM_SCOPE, :person_callsign, :target_person_callsign, :start_time,
                  :end_time, :event_name, :message, :page, event_filters: [])
  end

  def resolve_person_id(callsign)
    return nil if callsign.blank?

    Person.find_id_by_callsign(callsign)
  end

  def unknown_callsign?(callsign, person_id)
    callsign.present? && person_id.blank?
  end
end
