# frozen_string_literal: true

# The audit log kept by the first version of the Clubhouse. Read-only, and
# frozen: the last entry was written in October 2019.
class Admin::Clubhouse1LogController < ApplicationController
  layout "admin"

  authorize_role [Role::ADMIN, Role::TECH_NINJA]

  def index
    return unless prevent_if_ghd_server("Clubhouse 1 Log viewing")

    @form = Clubhouse1LogFilterForm.new(filter_params)

    user_person_id = resolve_person_id(@form.user_callsign)
    target_person_id = resolve_person_id(@form.target_callsign)

    @result = if unknown_person?(@form.user_callsign, user_person_id) ||
                 unknown_person?(@form.target_callsign, target_person_id)
                empty_result
              else
                Clubhouse1Log.find_for_query(
                  user_person_id:,
                  current_person_id: target_person_id,
                  start_time: @form.parsed_start_time,
                  end_time: @form.parsed_end_time,
                  event_prefixes: @form.event_prefixes,
                  event_text: @form.event_text.presence,
                  sort: @form.sort,
                  page: @form.page
                )
              end

    @logs = @result[:logs]
    @meta = @result[:meta]
  end

  private

  def filter_params
    scoped_params(Clubhouse1LogFilterForm::PARAM_SCOPE, :user_callsign, :target_callsign, :start_time,
                  :end_time, :event_text, :sort, :page, event_categories: [])
  end

  # The log names people by id. Most still hold the callsign they held then, but
  # some have been renamed and some no longer have a record at all, so a bare
  # number is taken as the id itself.
  #
  # The callsign is tried first even when it reads as a number, because a
  # callsign made only of digits is real -- one person holds "4748" today, and
  # reading it as an id would quietly answer with a different person's history.
  def resolve_person_id(callsign)
    return nil if callsign.blank?

    Person.find_id_by_callsign(callsign) ||
      (callsign.to_i if callsign.match?(/\A\d+\z/))
  end

  def unknown_person?(callsign, person_id)
    callsign.present? && person_id.blank?
  end

  def empty_result
    {
      logs: [],
      meta: {
        page: @form.page,
        page_size: Clubhouse1Log::PAGE_SIZE_DEFAULT,
        has_previous_page: @form.page > 1,
        has_next_page: false
      }
    }
  end
end
