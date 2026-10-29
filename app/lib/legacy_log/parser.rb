# frozen_string_literal: true

# Reads the first Clubhouse's shorthand for a SQL statement. Its logger
# (clubhouse-classic, Log::save in standard/controllers/log.php) replaced
# `INSERT INTO ` with `+`, `UPDATE ` with `=`, ` SET ` with `.`, `WHERE ` with
# `@`, `DELETE FROM ` with `-` and `AND ` with `&`, and dropped `VALUES`,
# single quotes, underscores and whitespace, so `UPDATE person SET
# status='alpha' WHERE id=1578` became `=person.status=alpha@id=1578`.
#
# The shorthand is lossy on purpose: a value holding a comma, `=`, `@` or `&`
# cannot be told from structure once its quotes are gone. So a statement is
# read only when its whole shape is recognised, values are never interpreted,
# and an id is claimed only from a plain positive integer in a place the
# statement names: a tuple column by position with every earlier value
# simple, a `col=N` assignment, or a `col=N` condition.
module LegacyLog::Parser
  OPERATIONS = { "+" => "insert", "=" => "update", "-" => "delete" }.freeze

  # Every table the first Clubhouse wrote to (ddl/ddl.sql and the ddlchanges
  # files), less the ones never converted: `log` itself, `sessions`, and
  # `person_xfield` by ruling 7.
  TABLES = %w[
    access_document access_document_changes access_document_delivery alert alert_person asset
    asset_attachment asset_person bmid broadcast broadcast_message contact_log event_dates feedback
    manual_review mentee_status person person_language person_mentor person_message person_position
    person_role person_slot position position_credit radio_eligible role slot ticket
    timesheet timesheet_log timesheet_missing trainee_status training xfield xgroup xoption
  ].freeze

  # The shorthand dropped underscores: `person_slot` reads `personslot`.
  TABLE_BY_FLAT = TABLES.index_by { |table| table.delete("_") }.freeze

  # An insert with no column list (views/maintenance_all.php) names these
  # columns in the DDL's order; no other table was written that way.
  POSITIONAL_COLUMNS = {
    "person_position" => %w[personid positionid],
    "person_role" => %w[personid roleid],
    "person_slot" => %w[personid slotid]
  }.freeze

  # The column that names the person a statement is about: personid, except
  # on the person table (its own id) and a contact log entry (its recipient).
  PERSON_COLUMN = Hash.new("personid").merge("person" => "id", "contact_log" => "recipientpersonid").freeze

  # The logger's truncation marker. For any statement over 100 characters (a
  # `> 100` where `> 499` was meant) it kept the text from the last `@` as a
  # tail and joined head and tail with `+`. A statement of 100 to 499
  # characters lost nothing: its head still ends inside, or at the end of, the
  # WHERE clause the tail repeats. A longer one lost whatever fell between
  # the two. The 2008 logger wrote `,+@` for the same thing.
  MARKER = /\A(?<head>.*)\+(?<tail>@[^@]*)\z/m

  # The column's width. A statement whose `@` sat early and whose text ran
  # long made the logger's head length negative, which PHP reads as "all but
  # the last few": the joined string ran past the column and the database
  # kept its first 500 characters, marker and all gone. A row this long with
  # no marker is that overflow, and cut.
  COLUMN_WIDTH = 500

  # A row the logger cut is exactly this long: 100 bytes from the 2008 logger
  # (a 99-byte head and the `+`), the column's width from the later one (a
  # 499-byte head). A shorter row ending in `+` lost nothing: the later logger
  # added the marker to any statement over 100 bytes, cut or not. Measured in
  # characters as well as bytes: a row with accented text was stored byte by
  # byte as characters (an `’` reads `â€™`), so its character count is the
  # logger's byte count.
  CUT_LENGTHS = [100, COLUMN_WIDTH].freeze

  NAME = /[a-z][a-z0-9]*/
  STATEMENT = /\A(?<operation>[+=-])`?(?<table>[a-z]+)`?(?<rest>.*)\z/m

  # A value the grammar accepts without reading it: a bare word (a number, a
  # keyword, a status, a date, an email), a quoted string (2018 only), a
  # function the first Clubhouse called, the password redaction, or an id
  # list.
  SIMPLE = %r{\A(?:[A-Za-z0-9._:+/@-]+|"[^"]*"|NOW\(\)|YEAR\(NOW\(\)\)|\[hidden\]|\(max\*\d+\)|\([\d,]+\)|[\d,]+\))\z}

  # What a tuple may hold where it names its person: an id, no one, or a
  # column of the SELECT a bulk insert copies from. `-1` is none of these.
  PERSON_VALUE = /\A(?:\d+|NULL|[a-z][a-z0-9.]*)\z/

  COLUMN = /`?#{NAME}`?/
  TUPLE = /\A\((?<columns>#{COLUMN}(?:,#{COLUMN})*)\)(?:\((?<values>.*)\)|SELECT(?<select>.*?)(?:FROM.*)?|\((?<cut>.*))\z/m
  POSITIONAL = /\A\((?<values>\d+(?:,\d+)*)\)\z/
  SET_FORM = /\A(?:\.|SET)(?<set>.*)\z/m

  # A condition's column, with or without its table and backticks, or a
  # function of one (`YEAR(begins)`), which names nothing to claim.
  CONDITION = /\A(?:[a-z]+\.)?(?:`?(?<column>#{NAME})`?|(?<function>[A-Za-z]+\([a-z]+\)))(?<operator>ISNOTNULL|ISNULL|!=|<=|>=|=|<|>|IN\(|in\()(?<value>.*)\z/m
  # A WHERE clause of flags alone, `assetauthorizedORvehiclepaperwork`: the
  # shorthand replaced only `AND `, so an OR stayed as it was.
  FLAGS = /\A#{NAME}(?:OR#{NAME})*\z/
  # Where a WHERE clause may start: at `@`, or at a `WHERE` the shorthand
  # left whole because a line break rather than a space followed it.
  WHERE_MARK = /@|WHERE/
  # A parenthesised group, `((password=...)OR(tpassword=...))`: read as one
  # condition that names nothing, when its parentheses balance and no WHERE
  # clause of its own hides inside.
  GROUP = /\A\([^@]*\)\z/m
  ASSIGNED_ID = /(?:\A|,)`?(?<column>[a-z0-9]*id)`?=(?<value>\d+)(?=,|\z)/
  ID_COLUMN = /id\z/

  # One read statement. columns and values describe an insert's tuple (the
  # values as the text between the parentheses), set an assignment list,
  # where the condition text, ids every `…id` column named with a plain
  # integer, and upsert whether the insert carried ON DUPLICATE KEY UPDATE.
  Statement = Struct.new(:operation, :table, :columns, :values, :set, :where, :ids, :upsert, keyword_init: true)

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
      return [event.delete_suffix("+"), CUT_LENGTHS.intersect?([event.bytesize, event.length])] if event.end_with?("+")

      [event, event.length == COLUMN_WIDTH]
    end

    # The operation and Classic table a statement is on, for the report:
    # "update person", "insert person_slot". A table that is not converted is
    # shown in parentheses; nil when the text is no statement at all.
    def family(text)
      statement = STATEMENT.match(text)
      return nil unless statement

      table = TABLE_BY_FLAT.fetch(statement[:table]) { "(#{statement[:table]})" }
      "#{OPERATIONS.fetch(statement[:operation])} #{table}"
    end

    # The statement a normalised event holds, or nil when its shape is not
    # one the grammar knows. truncated: lets an insert's tuple stay open,
    # since the logger cut it before the closing parenthesis.
    def parse(text, truncated: false)
      match = STATEMENT.match(text)
      table = match && TABLE_BY_FLAT[match[:table]]
      return nil unless table

      operation = OPERATIONS.fetch(match[:operation])
      attributes = if operation == "insert"
                     parse_insert(table, match[:rest], truncated)
                   else
                     parse_change(operation, match[:rest])
                   end
      Statement.new(operation:, table:, **attributes) if attributes
    end

    private

    def parse_insert(table, rest, truncated)
      rest, upsert, = rest.partition("ONDUPLICATEKEY")
      upsert = !upsert.empty?

      if (tuple = TUPLE.match(rest))
        return nil if tuple[:cut] && !truncated

        columns = tuple[:columns].delete("`").split(",")
        values = tuple[:values] || tuple[:select] || tuple[:cut]
        return nil unless person_value_ok?(table, columns, values)

        # A multi-row insert names its ids in its first tuple; the text keeps them all.
        { columns:, values:, ids: tuple_ids(columns, values.split("),(", 2).first), upsert: }
      elsif (positional = POSITIONAL.match(rest)) && (columns = POSITIONAL_COLUMNS[table])
        values = positional[:values]
        return nil unless values.count(",") + 1 == columns.size

        { columns:, values:, ids: tuple_ids(columns, values), upsert: }
      elsif (set = SET_FORM.match(rest))
        { set: set[:set], ids: assigned_ids(set[:set]), upsert: }
      end
    end

    # The WHERE clause starts at the right-most mark whose tail reads as one,
    # so an `@` inside an email in the SET clause, or inside a nested SELECT,
    # does not mislead it.
    def parse_change(operation, rest)
      rest.to_enum(:scan, WHERE_MARK).map { Regexp.last_match }.reverse_each do |mark|
        where = rest[mark.end(0)..].delete_suffix("LIMIT1")
        ids = parse_where(where)
        next unless ids

        head = rest[0...mark.begin(0)].sub(/[,+]+\z/, "")
        return change_attributes(operation, head, where, ids)
      end
      nil
    end

    def change_attributes(operation, head, where, ids)
      if operation == "update"
        set = SET_FORM.match(head)
        { set: set[:set], where:, ids: assigned_ids(set[:set]).merge(ids) } if set
      elsif head.empty?
        { where:, ids: }
      end
    end

    # The ids a WHERE clause names, or nil when any condition is not a
    # column, an operator and a simple value. A run of flags or a group is
    # readable and names nothing.
    def parse_where(text)
      return nil if text.empty?

      ids = {}
      text.split("&", -1).each do |condition|
        next if FLAGS.match?(condition) || group?(condition)

        match = CONDITION.match(condition)
        return nil unless match

        column = match[:column] || match[:function]
        return nil unless value_ok?(column, match[:operator], match[:value])

        id = IdList.id(match[:value]) if match[:operator] == "=" && ID_COLUMN.match?(column)
        ids[column] = id if id
      end
      ids
    end

    def group?(condition)
      GROUP.match?(condition) && condition.count("(") == condition.count(")")
    end

    # A null test takes no value; an equality may take none (`status=`, an
    # empty string with its quotes gone) unless the column is an id, where an
    # empty value is a statement the first Clubhouse wrote without one.
    def value_ok?(column, operator, value)
      return value.empty? if operator.start_with?("IS")
      return true if value.empty? && %w[= !=].include?(operator) && !ID_COLUMN.match?(column)

      SIMPLE.match?(value)
    end

    # The person column, read by position, holds a PERSON_VALUE -- or sits
    # past a value that is not simple, where position means nothing.
    def person_value_ok?(table, columns, values)
      index = columns.index(PERSON_COLUMN[table])
      return true unless index

      tokens = values.split(",", -1)
      return true if tokens[0...index].any? { |token| !SIMPLE.match?(token) }

      tokens[index].nil? || PERSON_VALUE.match?(tokens[index])
    end

    # The ids an insert's tuple names, column by column, stopping at the
    # first value that is not simple: a value holding a comma shifts every
    # value after it, so nothing past it can be trusted by position.
    def tuple_ids(columns, values)
      tokens = values.split(",", -1)
      ids = {}
      columns.each_with_index do |column, index|
        token = tokens[index]
        break if token.nil? || !SIMPLE.match?(token)

        id = IdList.id(token) if ID_COLUMN.match?(column)
        ids[column] = id if id
      end
      ids
    end

    def assigned_ids(set)
      set.scan(ASSIGNED_ID).to_h { |column, value| [column, IdList.id(value)] }.compact
    end
  end
end
