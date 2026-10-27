# frozen_string_literal: true

class Admin::ErrorLogsController < ApplicationController
  layout "admin"

  authorize_role [Role::ADMIN, Role::TECH_NINJA]

  def index
    @form = ErrorLogFilterForm.new(filter_params)

    person_id = resolve_person_id(@form.person_callsign)

    # A callsign no one has matches no row: the same query, with nothing to find.
    logs = unknown_callsign?(@form.person_callsign, person_id) ? ErrorLog.none : ErrorLog
    result = logs.find_for_query(
      person_id: person_id.presence,
      error_type: @form.error_type.presence,
      start_at: @form.parsed_start_time,
      ends_at: @form.parsed_end_time,
      last_day: @form.last_day,
      page: @form.page
    )

    @error_logs = result[:error_logs]
    @pagy = result[:pagy]
  end

  def purge
    count = ErrorLog.purge!(Current.person)

    redirect_to admin_error_logs_path, notice: "#{helpers.pluralize(count, 'error log entry')} deleted."
  end

  private

  def filter_params
    scoped_params(ErrorLogFilterForm::PARAM_SCOPE, :person_callsign, :error_type, :start_time, :end_time,
                  :last_day, :page)
  end

  def resolve_person_id(callsign)
    return nil if callsign.blank?

    Person.find_id_by_callsign(callsign)
  end

  def unknown_callsign?(callsign, person_id)
    callsign.present? && person_id.blank?
  end
end
