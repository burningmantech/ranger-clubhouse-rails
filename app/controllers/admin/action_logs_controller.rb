# frozen_string_literal: true

class Admin::ActionLogsController < ApplicationController
  layout "admin"

  authorize_role Role::ADMIN

  def index
    @form = ActionLogFilterForm.new(filter_params)

    person_id = resolve_person_id(@form.person_callsign)
    target_person_id = resolve_person_id(@form.target_person_callsign)

    @result = if unknown_callsign?(@form.person_callsign, person_id) || unknown_callsign?(@form.target_person_callsign,
                                                                                           target_person_id)
                empty_result(@form.page)
              else
                ActionLog.find_for_query(
                  person_id: person_id.presence,
                  target_person_id: target_person_id.presence,
                  start_time: @form.parsed_start_time,
                  end_time: @form.parsed_end_time,
                  events: @form.events,
                  message: @form.message.presence,
                  page: @form.page
                )
              end

    @action_logs = @result[:action_logs]
    @meta = @result[:meta]
  end

  private

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

  def empty_result(page)
    {
      action_logs: [],
      meta: {
        total: 0,
        total_pages: 0,
        page_size: ActionLog::PAGE_SIZE_DEFAULT,
        page: page,
        has_previous_page: page.to_i > 1,
        has_next_page: false,
        approximate_total: false
      }
    }
  end
end
