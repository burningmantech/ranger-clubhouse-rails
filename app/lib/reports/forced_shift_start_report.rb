# frozen_string_literal: true

# Shift starts that were forced past a sign-in blocker (Ember
# reports/forced-signins port).
#
# The timesheet row records that a start was forced and the reason typed at the
# time; which checks were overridden lives only in the audit log written beside
# it, so the two have to be read together.
#
# Upstream (app/Lib/Reports/ForcedSigninsReport.php) re-implements the old
# pre-2025 blocker conversion inline. TimesheetLog#decode_data already does it,
# so legacy rows are handed to the model rather than converted a second time
# here.
class ForcedShiftStartReport
  # blockers is always an array -- empty when no audit log survives, which is a
  # different statement from "no checks were overridden" and the view says so.
  Entry = Data.define(:timesheet_id, :person, :person_id, :callsign, :position_id,
                      :position_title, :on_duty, :blockers, :forced_by, :forced_by_id,
                      :reason) do
    # Which checks fired, by name, for the page's blocker filter. Audit-log JSON
    # arrives string-keyed and SignInBlocker writes symbols, so both are read.
    def blocker_names
      blockers.filter_map { |blocker| blocker[:blocker] || blocker["blocker"] }
    end
  end

  class << self
    def execute(year:)
      timesheets = year_timesheets(year)
      return [] if timesheets.empty?

      logs = forced_logs(timesheets.map(&:id))
      titles = Position.titles_by_id(timesheets.map(&:position_id).uniq)
      people = people_by_id(timesheets.map(&:person_id) + logs.values.map(&:create_person_id))

      timesheets.map { |timesheet| build_entry(timesheet, logs[timesheet.id], titles, people) }
                .sort_by { |entry| [entry.callsign.downcase, entry.on_duty] }
    end

    private

    # Narrow select: the report needs six columns and Timesheet carries the
    # review, verification, and correction fields alongside them.
    def year_timesheets(year)
      Timesheet.for_year(year)
               .where(was_signin_forced: true)
               .select(:id, :person_id, :position_id, :on_duty, :signin_force_reason)
               .to_a
    end

    # The forcing is recorded on one log per timesheet -- the check-in itself,
    # or the position correction that was forced. Earliest wins, as upstream's
    # first-of-group does, so a later forced correction cannot displace the
    # forced start the report is named for.
    def forced_logs(timesheet_ids)
      TimesheetLog.where(timesheet_id: timesheet_ids).order(:id)
                  .each_with_object({}) do |log, found|
        next if found.key?(log.timesheet_id) || log.data.blank?
        next if log.data["forced"].blank?

        found[log.timesheet_id] = log
      end
    end

    # Person is the widest table in the schema, so both the rangers and the
    # people who forced them come back as two columns in one query.
    def people_by_id(ids)
      Person.where(id: ids.compact.uniq).select(:id, :callsign).index_by(&:id)
    end

    def build_entry(timesheet, log, titles, people)
      person = people[timesheet.person_id]
      forced_by_id = log&.create_person_id

      Entry.new(timesheet_id: timesheet.id,
                person: person,
                person_id: timesheet.person_id,
                callsign: person&.callsign || "Deleted ##{timesheet.person_id}",
                position_id: timesheet.position_id,
                position_title: titles[timesheet.position_id],
                on_duty: timesheet.on_duty,
                blockers: blockers_for(log),
                forced_by: people[forced_by_id],
                forced_by_id: forced_by_id,
                reason: timesheet.signin_force_reason)
    end

    # A modern log carries the blockers verbatim; only the pre-2025 format needs
    # converting, and decode_data owns that. Reaching for it only on the legacy
    # rows also keeps its per-log position lookups off the common path.
    def blockers_for(log)
      return [] unless log

      return Array(log.data["blockers"]) if log.data["forced"] == true

      Array(log.decode_data["blockers"])
    end
  end
end
