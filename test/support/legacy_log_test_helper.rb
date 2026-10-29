# frozen_string_literal: true

# Rows of legacy_log as the conversion writes them, without running it.
module LegacyLogTestHelper
  # @param statement [String] the raw Clubhouse 1 event, kept in data
  # @param data [Hash, nil] the rest of data; an unknown row's by default
  def create_legacy_log(event: "unknown", statement: "=person.status=alpha@id=1", person: nil, target: nil,
                        created_at: Time.zone.parse("2015-06-01 12:00:00"), data: nil)
    log_id = (LegacyLog.maximum(:log_id) || 0) + 1
    data = { "event" => statement, "log_id" => log_id }.merge(data || { "target_source" => "session" })
    LegacyLog.insert!({ log_id:, person_id: person&.id, target_person_id: target&.id, event:, data:, created_at: })
    LegacyLog.find_by!(log_id:)
  end
end
