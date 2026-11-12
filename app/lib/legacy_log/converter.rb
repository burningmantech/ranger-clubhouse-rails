# frozen_string_literal: true

# Turns one row of the Clubhouse 1 log into a legacy_log row, or names why the
# row is skipped: the event name by the house rule, the actor from the signed-in
# user, the target from the statement, and data shaped as an action_logs
# row's.
module LegacyLog::Converter
  # Rulings of 2026-10-28, by the opening of the event: `#` events (logins,
  # requests, credits) map to no action; `!` diagnostics (errors, failed
  # logins) are not actions.
  SKIPS = { events: "#", diagnostics: "!" }.freeze

  # Tables never converted, by the shorthand's flat name: the session purges
  # (804,000 rows) are housekeeping, and custom fields -- their definitions
  # (xfield, xgroup, xoption) and a person's values -- have no Clubhouse 2 or
  # 3 equivalent (rulings 7 and 2026-11-12).
  SKIPPED_TABLES = { sessions: %w[sessions], custom_fields: %w[personxfield xfield xgroup xoption] }.freeze

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

  # A column of a table Clubhouse 3 no longer has keeps its Classic name,
  # but for the ids ActionLog's enrichment reads.
  ID_KEYS = { "personid" => "person_id", "slotid" => "slot_id", "positionid" => "position_id",
              "roleid" => "role_id" }.freeze

  # What action_logs keeps for a sign-up or a grant: the one id, and for a
  # position or a role a list of one.
  GRANT_DATA = {
    "person_slot" => ->(data) { data.slice("slot_id") },
    "person_position" => ->(data) { { "position_ids" => [data["position_id"]].compact } },
    "person_role" => ->(data) { { "role_ids" => [data["role_id"]].compact } }
  }.freeze

  # Where an assignment list splits: at a comma a column name follows. A
  # value holding `,word=` splits too; the statement is in data as written.
  ASSIGNMENT_BREAK = /,(?=`?#{LegacyLog::Parser::NAME}`?=)/

  class << self
    # Why a row is skipped, or nil when it is converted.
    def skip_reason(event)
      SKIPS.find { |_reason, opening| event.start_with?(opening) }&.first ||
        skipped_table(LegacyLog::Parser::STATEMENT.match(event)&.[](:table))
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

    def skipped_table(table)
      SKIPPED_TABLES.find { |_reason, tables| tables.include?(table) }&.first
    end

    # The target is the person the statement names, never the session's
    # person: that column held whoever the admin had open, wrong for every
    # bulk action. When the two differ the session's person is kept.
    #
    # data reads as an action_logs row's does: the row's own columns under
    # today's names, the ids as integers. The first Clubhouse logged no old
    # value, so an update holds the new value alone where action_logs holds
    # [old, new]. What only the first Clubhouse had is under "legacy".
    def converted(statement, event, id, session_person_id, truncated)
      target = statement.ids[LegacyLog::Parser::PERSON_COLUMN[statement.table]]
      names = column_names(statement.table)
      data = assignments(statement, truncated).to_h.merge(statement.ids).transform_keys { |column| names.fetch(column) { ID_KEYS.fetch(column, column) } }
      data = GRANT_DATA.fetch(statement.table).call(data) if EVENT_OVERRIDES.dig(statement.table, statement.operation)
      data["legacy"] = { "event" => event, "log_id" => id, "truncated" => (true if truncated),
                         "session_person_id" => (session_person_id unless session_person_id == target) }.compact
      { target_person_id: target, event: event_name(statement), data: }
    end

    # Ruling 6: an unknown row keeps the session's person as its target, and
    # says so in data. The whole event travels in data as well, so a later
    # conversion never needs the log table again.
    def unknown(event, id, session_person_id)
      { target_person_id: session_person_id, event: LegacyLog::UNKNOWN,
        data: { "legacy" => { "event" => event, "log_id" => id, "target_source" => "session" } } }
    end

    # Each column with its value, as text: an assignment list split at its
    # column names, or a single tuple whose values count as its columns do. A
    # value holding a comma throws that count off, and so does a cut or a
    # multi-row tuple: then nothing is paired.
    def assignments(statement, truncated)
      return statement.set.split(ASSIGNMENT_BREAK).map { |pair| pair.delete("`").partition("=").values_at(0, 2) } if statement.set
      return [] if statement.values.nil? || truncated

      values = statement.values.split(",", -1)
      (statement.columns.size == values.size) ? statement.columns.zip(values) : []
    end

    # A Classic table's columns by their flat name, from today's schema: the
    # shorthand dropped the underscores, and data names a column as
    # action_logs does. Empty for a table Clubhouse 3 no longer has.
    def column_names(table)
      @column_names ||= {}
      @column_names[table] ||= begin
        current = TABLE_RENAMES.fetch(table, table)
        connection = ActiveRecord::Base.connection
        connection.table_exists?(current) ? connection.columns(current).to_h { |column| [column.name.delete("_"), column.name] } : {}
      end
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
