# frozen_string_literal: true

# A year of timesheets: which rows a given reader may see, and what each row is
# worth.
#
# Timesheets by Callsign and Timesheet by Position are one report grouped two
# ways. The visibility rule decides what a scoped reader is shown, and the
# credit arithmetic decides every number on both pages -- so neither may live on
# one report and be copied into the other. Two copies are two chances to
# disagree about what a reader is allowed to read.
#
# Included into the report classes, which supply their own grouping and totals.
module TimesheetYearReport
  extend ActiveSupport::Concern

  # Upstream's status strings, carried over so each page's three states and the
  # API's stay the same three.
  FULL_REPORT = "full-report"
  PARTIAL_REPORT = "partial-report"
  NO_MEMBERSHIP = "no-membership"

  # Admin and Full Report Access read every position; everyone else who passes a
  # report's own gate reads only the positions their Cadres, Delegations, and
  # managed teams own.
  FULL_ACCESS_ROLES = [Role::ADMIN, Role::FULL_REPORT_ACCESS].freeze

  class_methods do
    # {timesheet id => credits}, computed in one pass.
    #
    # The arithmetic itself lives in TimesheetCredits, so a report can price
    # rows without also taking on the visibility rules below -- the two are
    # separate questions, and only the pages that group a whole year need both.
    def credits_by_id(rows) = TimesheetCredits.credits_by_id(rows)

    # The positions a partial-report reader may see. Public so a page can ask
    # the question directly -- the by-position drill-down admits a position the
    # reader owns even in a year it holds no entries, which cannot be inferred
    # from a row count.
    def visible_position_ids(viewer)
      team_ids = PersonTeam.retrieve_cadre_membership_ids(viewer.id) +
                 TeamManager.retrieve_team_ids_for_person(viewer.id)
      return [] if team_ids.empty?

      Position.where(team_id: team_ids).pluck(:id)
    end

    # The ids this reader is scoped to, or nil when they may read every
    # position. Callers that need the ids for their own question -- the
    # by-position drill-down asks whether one position is readable -- take them
    # from here and hand them straight to scope_for, so the three queries are
    # paid for once per request rather than once per asker.
    def readable_position_ids(viewer)
      return nil if viewer.has_role?(FULL_ACCESS_ROLES)

      visible_position_ids(viewer)
    end

    private

    # nil means "this reader belongs to no team that owns positions" -- the
    # no-membership state, which is not the same as a year with no entries.
    def visible_scope(year:, viewer:)
      scope_for(year, readable_position_ids(viewer))
    end

    # The one place a year is narrowed to what a reader may see, so no caller
    # can spell the rule differently.
    def scope_for(year, position_ids)
      base = Timesheet.for_year(year)
      return base if position_ids.nil?
      return nil if position_ids.empty?

      base.where(position_id: position_ids)
    end

    def status_for(viewer)
      viewer.has_role?(FULL_ACCESS_ROLES) ? FULL_REPORT : PARTIAL_REPORT
    end
  end
end
