# frozen_string_literal: true

# The Clubhouse 1 audit log (Clubhouse1Log, 2008 to 2019) converted to Action
# Log form, one row per convertible `log` row, keyed by log_id. Only
# `bin/rails legacy_log:convert` (LegacyLog::Conversion) writes here, through
# upsert_all; the app reads.
#
# person_id is who acted: log.user_person_id, the signed-in user. (The brief
# that asked for this table had the two columns the other way round; the
# Classic logger, Log::save in standard/controllers/log.php, and the DDL
# comments on the table say this.) target_person_id is who it was done to: for
# a converted row the person the statement names, for an `unknown` row the
# session's current_person_id, and data.target_source says which.
class LegacyLog < ApplicationRecord
  self.table_name = "legacy_log"

  # created_at is copied from the log; nothing stamps it.
  self.record_timestamps = false

  PAGE_SIZE_DEFAULT = 50

  # The event of a row the conversion could not read with confidence.
  UNKNOWN = "unknown"

  belongs_to :person, optional: true
  belongs_to :target_person, class_name: "Person", optional: true

  serialize :data, coder: JSON

  # The session's person, loaded a page at a time by find_for_query: most
  # timesheet rows carry one, so a lookup per row would be fifty a page.
  attr_accessor :session_person

  # Nothing writes here through a record: the task writes its rows in bulk.
  def readonly?
    true
  end

  # The session's person, kept when the statement named someone else.
  def session_person_id
    data["session_person_id"] if data.is_a?(Hash)
  end

  # Whether the first Clubhouse cut the statement short.
  def truncated?
    data.is_a?(Hash) && data["truncated"] == true
  end

  # What the row did, in a line, read from data (ruling 8: the table keeps
  # no message): an insert's columns paired with its values, an update's
  # assignments and conditions, a delete's conditions, or the raw event of an
  # unknown row.
  def summary
    return "" unless data.is_a?(Hash)
    return data["event"].to_s if event == UNKNOWN

    where = ("where #{data["where"].gsub("&", " and ")}" if data["where"])
    [data["set"] || tuple_summary, where].compact.join(" ")
  end

  class << self
    include Pagy::Method

    # ActionLog.find_for_query without the request metadata this table has no
    # columns for: a page of rows, newest first, paged by Pagy's countless mode
    # (a row past the page says whether another follows), and the total the
    # pager names beside it -- counted, or estimated from the ids when nothing
    # filters.
    #
    # @param events [Array<String>] exact event names, or patterns with `%`
    # @return [Hash] { legacy_logs:, pagy:, total:, approximate_total: }
    def find_for_query(person_id: nil, target_person_id: nil, start_time: nil, end_time: nil, events: [],
                       page: 1, page_size: PAGE_SIZE_DEFAULT)
      scope = all
      scope = scope.where(person_id:) if person_id.present?
      scope = scope.where(target_person_id:) if target_person_id.present?
      scope = scope.where(events_condition(events)) if events.present?
      scope = scope.where(created_at: start_time..) if start_time.present?
      scope = scope.where(created_at: ..end_time) if end_time.present?

      filtered = [person_id, target_person_id, events, start_time, end_time].any?(&:present?)
      total = filtered ? scope.count : estimated_total(scope)
      # Nothing to fetch on a page past the last row -- a stale or hand-typed
      # page number would otherwise walk an offset of millions for nothing. The
      # estimate is never below the true count, so this never hides a row.
      scope = scope.none if total <= (page - 1) * page_size

      # The id breaks ties: the log kept whole seconds, and the first Clubhouse
      # wrote in bursts.
      scope = scope.order(created_at: :desc, id: :desc).includes(:person, :target_person)
      pagy, rows = pagy(:countless, scope, page:, limit: page_size, request: { params: {} })
      load_session_people(rows)

      # An estimate only where the ids gave one: a search for no one has none.
      { legacy_logs: rows, pagy:, total:, approximate_total: !filtered && total.positive? }
    end

    private

    # The exact names as one IN, each `%` pattern as a LIKE, any of them
    # matching.
    def events_condition(events)
      exact, patterns = events.partition { |event| event.exclude?("%") }
      conditions = patterns.map { |pattern| arel_table[:event].matches(pattern) }
      conditions.unshift(arel_table[:event].in(exact)) if exact.any?
      conditions.reduce { |combined, condition| combined.or(condition) }
    end

    def load_session_people(rows)
      ids = rows.filter_map(&:session_person_id).uniq
      return if ids.empty?

      people = Person.where(id: ids).index_by(&:id)
      rows.each { |row| row.session_person = people[row.session_person_id] }
    end

    # count(*) walks every row; the id range is an index read at either end.
    # Asked of the scope, so a search on none finds none.
    def estimated_total(scope)
      first_id = scope.reorder(:id).pick(:id)
      first_id ? scope.reorder(id: :desc).pick(:id) - first_id + 1 : 0
    end
  end

  private

  # The values text paired with its columns when the counts agree; a value
  # holding a comma throws the pairing off, and then the text stands alone.
  def tuple_summary
    return unless data["values"]

    columns = data["columns"].to_s.split(",")
    values = data["values"].split(",", -1)
    return data["values"] unless columns.size == values.size

    columns.zip(values).map { |column, value| "#{column}=#{value}" }.join(", ")
  end
end
