# frozen_string_literal: true

# Read-only view of every request the Clubhouse answered: searched by person,
# outcome, verb, time range, and address, or watched live as each one arrives.
class Admin::RequestLogsController < ApplicationController
  layout "admin"

  authorize_role [Role::ADMIN, Role::TECH_NINJA]

  def index
    return live if params[:mode] == "live"

    @form = RequestLogFilterForm.new(filter_params)

    person_id = resolve_person_id(@form.person_callsign)

    @result = if unknown_callsign?(@form.person_callsign, person_id)
                empty_result(@form.page)
              else
                RequestLog.find_for_query(
                  person_id: person_id,
                  status_class: @form.selected_status_class,
                  http_method: @form.selected_http_method,
                  start_time: @form.parsed_start_time,
                  end_time: @form.parsed_end_time,
                  ip: @form.ip.presence,
                  page: @form.page
                )
              end

    @logs = @result[:request_log]
    @meta = @result[:meta]
  end

  def expire
    count = RequestLog.expire

    redirect_to admin_request_logs_path, notice: "#{helpers.pluralize(count, 'request log entry')} deleted."
  end

  private

  # The Live mode: the newest rows now, and RequestLogLiveChannel sends what
  # arrives after them. As many as the channel looks back over, so its first
  # tick finds the page's own rows. Rendered from index so the mode toggle is
  # one page.
  def live
    @live_logs = RequestLog.newest_first.limit(RequestLogLiveChannel::LOOKBACK).to_a
    @logging_on = Setting.get_value(Setting::REQUEST_LOG_ENABLED)
    render :index
  end

  def filter_params
    scoped_params(RequestLogFilterForm::PARAM_SCOPE, :person_callsign, :status_class, :http_method,
                  :start_time, :end_time, :ip, :page)
  end

  # A bare number is a person id, matching the hint the search field gives.
  def resolve_person_id(callsign)
    return nil if callsign.blank?
    return callsign.to_i if callsign.match?(/\A\d+\z/)

    Person.find_id_by_callsign(callsign)
  end

  def unknown_callsign?(callsign, person_id)
    callsign.present? && person_id.blank?
  end

  def empty_result(page)
    {
      request_log: [],
      meta: { total: 0, total_pages: 0, page_size: RequestLog::PAGE_SIZE_DEFAULT, page: page }
    }
  end
end
