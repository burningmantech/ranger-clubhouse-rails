# frozen_string_literal: true

# The Clubhouse 1 audit log converted to Action Log form (LegacyLog).
# Read-only: the conversion task fills the table, and the page shows it.
class Admin::LegacyLogController < ApplicationController
  layout "admin"

  authorize_role [Role::ADMIN, Role::TECH_NINJA]

  def index
    return unless prevent_if_ghd_server("Legacy Clubhouse 1 Log viewing")

    @form = LegacyLogFilterForm.new(filter_params)
    @result = LegacyLog.find_for_query(
      person_id: resolve_person_id(@form.person_callsign),
      target_person_id: resolve_person_id(@form.target_person_callsign),
      start_time: @form.parsed_start_time,
      end_time: @form.parsed_end_time,
      events: @form.events,
      page: @form.page
    )
    @legacy_logs = @result[:legacy_logs]
    @pagy = @result[:pagy]
  end

  private

  def filter_params
    scoped_params(LegacyLogFilterForm::PARAM_SCOPE, :person_callsign, :target_person_callsign, :start_time,
                  :end_time, :event_name, :page, event_filters: [])
  end

  # The log names people by id, and some no longer have a record, so a bare
  # number is taken as the id itself -- after the callsign, because a callsign
  # made only of digits is real (Admin::Clubhouse1LogController says why). A
  # callsign no one holds falls back to an id no one holds, so it finds nothing
  # rather than everything: the conversion stores the log's 0 as NULL.
  def resolve_person_id(callsign)
    return nil if callsign.blank?

    Person.find_id_by_callsign(callsign) || IdList.id(callsign) || 0
  end
end
