# frozen_string_literal: true

# Turns one row of the Clubhouse 1 log into a legacy_log row, or names why the
# row is skipped: the event name by the house rule, the actor from the signed-in
# user, the target from the statement, and what the statement named in data.
module LegacyLog::Converter
  # Rulings of 2026-10-28, by the opening of the event: `#` events (logins,
  # requests, credits) map to no action; `!` diagnostics (errors, failed
  # logins) are not actions.
  SKIPS = { events: "#", diagnostics: "!" }.freeze

  # Tables never converted, by the shorthand's flat name: the session purges
  # (804,000 rows) are housekeeping, and a custom-field value (ruling 7) has
  # no Clubhouse 2 or 3 equivalent.
  SKIPPED_TABLES = { sessions: "sessions", custom_fields: "personxfield" }.freeze

  # Every reason a row is skipped, with what marks it, for the report.
  SKIP_REASONS = { **SKIPS, **SKIPPED_TABLES }.freeze

  # The house rule names an event after the table and the operation
  # (ApplicationRecord#record_audit); these are the names Clubhouse 2 chose
  # instead, so the Action Logs categories find the legacy rows too.
  EVENT_OVERRIDES = {
    "person_slot" => { "insert" => "person-slot-add", "delete" => "person-slot-remove" },
    "person_position" => { "insert" => "person-position-add", "delete" => "person-position-remove" },
    "person_role" => { "insert" => "person-role-add", "delete" => "person-role-remove" }
  }.freeze

  # Tables Clubhouse 2 renamed; the event carries today's name.
  TABLE_RENAMES = { "asset_person" => "person_asset", "alert_person" => "person_alert" }.freeze

  OPERATION_SUFFIX = { "insert" => "create", "update" => "update", "delete" => "delete" }.freeze

  # The ids under the keys ActionLog's enrichment reads; every other id keeps
  # its Classic name.
  ID_KEYS = { "slotid" => "slot_id", "positionid" => "position_id", "roleid" => "role_id" }.freeze

  class << self
    # Why a row is skipped, or nil when it is converted.
    def skip_reason(event)
      SKIPS.find { |_reason, opening| event.start_with?(opening) }&.first ||
        SKIPPED_TABLES.key(LegacyLog::Parser::STATEMENT.match(event)&.[](:table))
    end

    # The five columns of a log row, in table order. The first Clubhouse
    # wrote 0 as well as NULL for no one; nonzero? reads both as nil.
    #
    # @return [Array(Hash, String)] the legacy_log row and the statement's family
    def convert(id, user_person_id, current_person_id, occurred, event)
      text, truncated = LegacyLog::Parser.normalize(event)
      statement = LegacyLog::Parser.parse(text, truncated:)
      session_person_id = current_person_id&.nonzero?
      row = { log_id: id, person_id: user_person_id&.nonzero?, created_at: occurred }
      row.merge!(statement ? converted(statement, event, id, session_person_id, truncated) : unknown(event, id, session_person_id))
      [row, LegacyLog::Parser.family(text)]
    end

    private

    # The target is the person the statement names, never the session's
    # person: that column held whoever the admin had open, wrong for every
    # bulk action. When the two differ the session's person is kept in data.
    # The columns travel as one text, so the detail row shows them on a line.
    def converted(statement, event, id, session_person_id, truncated)
      person_column = LegacyLog::Parser::PERSON_COLUMN[statement.table]
      target = statement.ids[person_column]
      data = { "event" => event, "log_id" => id, "table" => statement.table, "operation" => statement.operation,
               "columns" => statement.columns&.join(","), "values" => statement.values, "set" => statement.set,
               "where" => statement.where, "truncated" => (true if truncated),
               **statement.ids.except(person_column).transform_keys { |column| ID_KEYS.fetch(column, column) },
               "session_person_id" => (session_person_id unless session_person_id == target) }.compact
      { target_person_id: target, event: event_name(statement), data: }
    end

    # Ruling 6: an unknown row keeps the session's person as its target, and
    # says so in data. The whole event travels in data as well, so a later
    # conversion never needs the log table again.
    def unknown(event, id, session_person_id)
      { target_person_id: session_person_id, event: LegacyLog::UNKNOWN,
        data: { "event" => event, "log_id" => id, "target_source" => "session" } }
    end

    # The Classic table with its underscores turned to hyphens and the
    # operation after it; an insert with ON DUPLICATE KEY UPDATE is an update.
    def event_name(statement)
      EVENT_OVERRIDES.dig(statement.table, statement.operation) ||
        "#{TABLE_RENAMES.fetch(statement.table, statement.table).tr("_", "-")}-" \
        "#{statement.upsert ? "update" : OPERATION_SUFFIX.fetch(statement.operation)}"
    end
  end
end
