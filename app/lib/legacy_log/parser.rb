# frozen_string_literal: true

# Reads the first Clubhouse's shorthand for a SQL statement. Its logger
# (clubhouse-classic, Log::save in standard/controllers/log.php) replaced
# `INSERT INTO ` with `+`, `UPDATE ` with `=`, ` SET ` with `.`, `WHERE ` with
# `@`, `DELETE FROM ` with `-` and `AND ` with `&`, and dropped `VALUES`,
# single quotes, underscores and whitespace, so `UPDATE person SET
# status='alpha' WHERE id=1578` became `=person.status=alpha@id=1578`.
#
# Until the grammar that reads a statement lands here, this undoes the
# logger's truncation marker and names the family a statement belongs to.
module LegacyLog::Parser
  OPERATIONS = { "+" => "insert", "=" => "update", "-" => "delete" }.freeze

  # Every table the first Clubhouse wrote to (ddl/ddl.sql and the ddlchanges
  # files), less `log` itself and `sessions`, which are not converted.
  TABLES = %w[
    access_document access_document_changes access_document_delivery alert alert_person asset
    asset_attachment asset_person bmid broadcast broadcast_message contact_log event_dates feedback
    manual_review mentee_status person person_language person_mentor person_message person_position
    person_role person_slot person_xfield position position_credit radio_eligible role slot ticket
    timesheet timesheet_log timesheet_missing trainee_status training xfield xgroup xoption
  ].freeze

  # The shorthand dropped underscores: `person_slot` reads `personslot`.
  TABLE_BY_FLAT = TABLES.index_by { |table| table.delete("_") }.freeze

  # The logger's truncation marker. For any statement over 100 characters (a
  # `> 100` where `> 499` was meant) it kept the text from the last `@` as a
  # tail and joined head and tail with `+`. A statement of 100 to 499
  # characters lost nothing: its head still ends inside, or at the end of, the
  # WHERE clause the tail repeats. A longer one lost whatever fell between
  # the two. The 2008 logger wrote `,+@` for the same thing.
  MARKER = /\A(?<head>.*)\+(?<tail>@[^@]*)\z/m

  # A row the logger cut is exactly this long: 100 bytes from the 2008 logger
  # (a 99-byte head and the `+`), 500 from the later one (a 499-byte head). A
  # shorter row ending in `+` lost nothing: the later logger added the marker
  # to any statement over 100 bytes, cut or not.
  CUT_LENGTHS = [100, 500].freeze

  STATEMENT = /\A(?<operation>[+=-])`?(?<table>[a-z]+)/

  class << self
    # The statement as the logger saw it, and whether part of it is missing.
    #
    # @return [Array(String, Boolean)] the text, and a truncated flag
    def normalize(event)
      if (marker = MARKER.match(event))
        head, tail = marker[:head], marker[:tail]
        at = head.rindex("@")
        # The head already holds the WHERE clause the tail repeats, whole or
        # cut partway: the tail completes it and nothing was lost.
        return [head[0...at] + tail, false] if at && tail.start_with?(head[at..])

        return [head.sub(/[,+]+\z/, "") + tail, true]
      end
      return [event.delete_suffix("+"), CUT_LENGTHS.include?(event.bytesize)] if event.end_with?("+")

      [event, false]
    end

    # The operation and Classic table a statement is on, for the report:
    # "update person", "insert person_slot". A table the first Clubhouse never
    # had is shown in parentheses; nil when the text is no statement at all.
    def family(text)
      statement = STATEMENT.match(text)
      return nil unless statement

      table = TABLE_BY_FLAT.fetch(statement[:table]) { "(#{statement[:table]})" }
      "#{OPERATIONS.fetch(statement[:operation])} #{table}"
    end
  end
end
