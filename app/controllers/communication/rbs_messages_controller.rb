# frozen_string_literal: true

# Every text, email, and Clubhouse message the broadcast system recorded,
# outgoing and incoming. An outgoing row may never have gone: its status says
# what became of it.
class Communication::RbsMessagesController < ApplicationController
  layout "communication"

  authorize_role [Role::ADMIN, Role::TECH_NINJA],
                 message: "Admin or Tech Ninja role required to read the message log."

  # Messages begin in 2018; the pandemic years hold rows too.
  self.year_floor = 2018

  before_action :setup_year

  def index
    @form = RbsMessageLogFilterForm.new(filter_params)

    result = BroadcastMessage.find_for_query(
      year: @year,
      person_id: resolve_person_id(@form.callsign),
      direction: @form.direction,
      status: @form.status.presence,
      page: @form.page
    )

    @messages = result[:messages].to_a
    @meta = result[:meta]
    @inbound_count = BroadcastMessage.for_year(@year).where(direction: "inbound").count
    @unknown_count = BroadcastMessage.for_year(@year).where(status: Broadcast::STATUS_UNKNOWN_PHONE).count
  end

  private

  def filter_params
    scoped_params(RbsMessageLogFilterForm::PARAM_SCOPE, :callsign, :direction, :page, status: [])
  end

  # Falls back to an id no one holds, so a callsign matching no one returns no
  # messages. Dropping the search instead would quietly hand back the whole log.
  def resolve_person_id(callsign)
    return nil if callsign.blank?

    Person.find_id_by_callsign(callsign) || 0
  end
end
