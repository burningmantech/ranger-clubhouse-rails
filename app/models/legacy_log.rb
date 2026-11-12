# frozen_string_literal: true

# The Clubhouse 1 audit log (Clubhouse1Log, 2008 to 2019) converted to Action
# Log form, one row per convertible `log` row, keyed by log_id. The table has
# action_logs' columns but message (the first Clubhouse wrote none: what a row
# did is read from data) and this class is ActionLog on it, so the search, the
# slot, position and role lookups and the page's table are the same code. The
# two tables are never merged or read together: this one is not a reliable
# record (owner's ruling, 2026-11-10). Only `bin/rails legacy_log:convert`
# (LegacyLog::Conversion) writes here, through upsert_all; the app reads.
#
# person_id is who acted: log.user_person_id, the signed-in user. (The brief
# that asked for this table had the two columns the other way round; the
# Classic logger, Log::save in standard/controllers/log.php, and the DDL
# comments on the table say this.) target_person_id is who it was done to: for
# a converted row the person the statement names, for an `unknown` row the
# session's current_person_id, and data.legacy.target_source says which.
# data.legacy holds what only the first Clubhouse had: the event as written,
# the log id, the session's person, whether the statement was cut.
class LegacyLog < ActionLog
  self.table_name = "legacy_log"

  # created_at is copied from the log; nothing stamps it.
  self.record_timestamps = false

  # The event of a row the conversion could not read with confidence.
  UNKNOWN = "unknown"

  # The session's person, loaded a page at a time by find_for_query: most
  # timesheet rows carry one, so a lookup per row would be fifty a page.
  attr_accessor :session_person

  # Nothing writes here through a record: the task writes its rows in bulk.
  def readonly?
    true
  end

  # The session's person, kept when the statement named someone else.
  def session_person_id
    legacy["session_person_id"]
  end

  # Whether the first Clubhouse cut the statement short.
  def truncated?
    legacy["truncated"] == true
  end

  class << self
    # ActionLog.find_for_query, with each row's session person.
    def find_for_query(...)
      super.tap { |result| load_session_people(result[:action_logs]) }
    end

    private

    def load_session_people(rows)
      ids = rows.filter_map(&:session_person_id).uniq
      return if ids.empty?

      people = Person.where(id: ids).index_by(&:id)
      rows.each { |row| row.session_person = people[row.session_person_id] }
    end
  end

  private

  def legacy
    (data.is_a?(Hash) && data["legacy"].is_a?(Hash)) ? data["legacy"] : {}
  end
end
