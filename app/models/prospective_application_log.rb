# frozen_string_literal: true

class ProspectiveApplicationLog < ApplicationRecord
  self.table_name = "prospective_application_log"

  # Application was imported from Salesforce
  ACTION_CREATED = "created"
  ACTION_EMAILED = "emailed"
  ACTION_IMPORTED = "imported"
  ACTION_UPDATED = "updated"

  serialize :data, coder: JSON

  belongs_to :person, optional: true
  belongs_to :prospective_application

  def self.record(application_id, action, data = nil)
    create!(
      prospective_application_id: application_id,
      action: action,
      person_id: Current.person_id,
      data: data.presence
    )
  end

  # Resolve every assigned-person id appearing in the given logs to a
  # callsign, in one query. Pass the result to #meta when rendering a list.
  def self.assigned_callsign_map(logs)
    ids = logs.flat_map { |log| Array(log.data&.dig("assigned_person_id")) }.compact.uniq
    Person.where(id: ids).pluck(:id, :callsign).to_h
  end

  # Resolve assigned-person id transitions to callsigns for display.
  def meta(callsigns = nil)
    return nil unless action == ACTION_UPDATED

    assigned = data&.dig("assigned_person_id")
    return nil unless assigned

    from_id, to_id = assigned
    { assigned_person: [callsign_for(from_id, callsigns), callsign_for(to_id, callsigns)] }
  end

  private

  def callsign_for(person_id, callsigns)
    return nil unless person_id
    return callsigns[person_id] if callsigns

    Person.where(id: person_id).pick(:callsign)
  end
end
