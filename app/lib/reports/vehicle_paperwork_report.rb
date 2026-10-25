# frozen_string_literal: true

# Builds the /vehicles/paperwork roster (Ember reports/vehicle-paperwork port of
# App\Lib\Reports\VehiclePaperworkReport).
#
# Everyone who has signed the Vehicle Use Protocol, has an approved Motor
# Vehicle Record, or is eligible to request one -- through an eligible team, a
# granted Motor Vehicle Record position, a shift sign-up in an eligible
# position, or the Event Info checkboxes.
#
# Upstream reports on the current year only. Here the year is a parameter so the
# page can carry the same year selector as its sibling registry -- but only the
# sign-up and person_event queries are genuinely year-scoped. Team membership
# and position grants carry no year at all: person_team and person_position
# record who is on a team or holds a position NOW, and person_team_log and
# person_position_log only begin in 2022-23, so they cannot say who held what
# before then either. So both are read for the current year only, exactly as
# VehicleRegistry does with its own current-year-only enrichment, and any other
# year reports "not checked" rather than passing today's rosters off as history.
class VehiclePaperworkReport
  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  APPROVED = "approved"
  NOT_APPROVED = "not_approved"
  ELIGIBLE = "eligible"
  NOT_ELIGIBLE = "not_eligible"

  # Every filter the page offers, in the order the panel shows them. The four
  # yes/no filters read a predicate off the row; the four list filters ask
  # whether a title is in one of the row's collections.
  FLAG_FILTERS = { mvr_approval: :record_approved,
                   mvr_eligible: :mvr_eligible?,
                   pvr_approval: :pvr_approved,
                   pvr_eligible: :pvr_eligible? }.freeze

  LIST_FILTERS = { mvr_team: :mvr_teams,
                   mvr_position: :mvr_positions,
                   pvr_team: :pvr_teams,
                   pvr_position: :pvr_positions }.freeze

  FILTER_KEYS = (FLAG_FILTERS.keys + LIST_FILTERS.keys + [:callsign]).freeze

  Signup = Struct.new(:position_title, :begins, keyword_init: true)

  # One person's paperwork. The five flags come from person_event; the five
  # lists from teams, position grants and shift sign-ups.
  Row = Struct.new(:person, :signed_vup, :record_approved, :pvr_approved,
                   :mvr_checkbox, :pvr_checkbox,
                   :mvr_teams, :mvr_positions, :mvr_signups,
                   :pvr_teams, :pvr_positions, keyword_init: true) do
    def callsign = person.callsign

    def status = person.status

    def sort_key = person.callsign.to_s.downcase

    # The derived "eligible" columns: the checkbox is only one of the ways in.
    def mvr_eligible? = mvr_checkbox || mvr_teams.any? || mvr_positions.any? || mvr_signups.any?

    def pvr_eligible? = pvr_checkbox || pvr_teams.any? || pvr_positions.any?
  end

  # #rows is what the filters left; the counts always describe the whole year,
  # so the stat boxes do not move as someone narrows the list.
  #
  # The four *_options lists are built from the UNFILTERED roster, so choosing a
  # team never removes the other teams from the picker -- otherwise a filter
  # could not be widened again without clearing it first.
  #
  # memberships_checked is false for any year but the current one -- see the
  # note at the top of the file. The views and the export must say "not
  # checked" there rather than render an empty team or granted-position list as
  # a confirmed absence.
  Result = Struct.new(:rows, :total_count, :vup_count, :record_approved_count,
                      :pvr_approved_count, :mvr_eligible_count, :pvr_eligible_count,
                      :mvr_team_options, :mvr_position_options,
                      :pvr_team_options, :pvr_position_options,
                      :memberships_checked, keyword_init: true) do
    def any? = rows.any?

    def empty_year? = total_count.zero?

    def memberships_checked? = memberships_checked
  end

  class << self
    # year:    event year to report on
    # filters: any of FILTER_KEYS; blank or "all" means no narrowing
    def for_year(year, filters = {})
      rows = build_rows(year).sort_by(&:sort_key)

      Result.new(rows: filter(rows, filters),
                 total_count: rows.size,
                 vup_count: rows.count(&:signed_vup),
                 record_approved_count: rows.count(&:record_approved),
                 pvr_approved_count: rows.count(&:pvr_approved),
                 mvr_eligible_count: rows.count(&:mvr_eligible?),
                 pvr_eligible_count: rows.count(&:pvr_eligible?),
                 mvr_team_options: titles_in(rows, :mvr_teams),
                 mvr_position_options: titles_in(rows, :mvr_positions),
                 pvr_team_options: titles_in(rows, :pvr_teams),
                 pvr_position_options: titles_in(rows, :pvr_positions),
                 memberships_checked: year == Current.year)
    end

    private

    # Every team or position title actually present on somebody in the roster,
    # so the picker never offers a choice that would empty the table.
    def titles_in(rows, collection)
      rows.flat_map { |row| row.public_send(collection) }.uniq.sort_by(&:downcase)
    end

    def build_rows(year)
      # person_team and person_position have no year column, so these are
      # always "now". Reading them for a past year would put today's team or
      # grant in that year's eligibility columns and count it in that year's
      # stat boxes.
      current = year == Current.year
      mvr_teams, pvr_teams = current ? teams_by_person_id : [{}, {}]
      mvr_positions = current ? granted_mvr_positions_by_person_id : {}
      pvr_positions = signup_positions_by_person_id(year, :pvr_eligible)
      mvr_signups = signups_by_person_id(year)
      events = event_flags_by_person_id(year)

      ids = (mvr_teams.keys + pvr_teams.keys + mvr_positions.keys +
             pvr_positions.keys + mvr_signups.keys + events.keys).uniq
      return [] if ids.empty?

      people(ids).map do |person|
        event = events[person.id]

        Row.new(person:,
                signed_vup: event&.signed_motorpool_agreement || false,
                record_approved: event&.org_vehicle_insurance || false,
                pvr_approved: event&.signed_personal_vehicle_agreement || false,
                mvr_checkbox: event&.mvr_eligible || false,
                pvr_checkbox: event&.may_request_stickers || false,
                mvr_teams: mvr_teams[person.id] || [],
                mvr_positions: mvr_positions[person.id] || [],
                mvr_signups: mvr_signups[person.id] || [],
                pvr_teams: pvr_teams[person.id] || [],
                pvr_positions: pvr_positions[person.id] || [])
      end
    end

    # Only the three columns the roster shows. Full Person records so the table
    # can hand them to callsign_link.
    def people(ids)
      Person.where(id: ids).select(:id, :callsign, :status)
    end

    # Active teams flagged for either request type, split into the two lists a
    # row needs. One query: a team can be flagged for both.
    def teams_by_person_id
      base = Team.joins(:person_team).where(active: true)
      rows = base.where(mvr_eligible: true)
                 .or(base.where(pvr_eligible: true))
                 .select("team.title", "team.mvr_eligible", "team.pvr_eligible",
                         "person_team.person_id AS person_id")
                 .order(:title)

      mvr = {}
      pvr = {}
      rows.each do |row|
        person_id = row.person_id.to_i
        (mvr[person_id] ||= []) << row.title if row.mvr_eligible
        (pvr[person_id] ||= []) << row.title if row.pvr_eligible
      end

      [mvr, pvr]
    end

    # Active Motor Vehicle Record eligible positions the person holds, whether
    # or not they signed up for a shift in one. Upstream moved this list from
    # sign-ups to grants (api 565d5fa1), but its query skips the eligibility
    # filter and a null guard drops the other positions only after their
    # holders have joined the roster -- every holder of any active position.
    # Filtering in the query lists only people with an eligible grant.
    def granted_mvr_positions_by_person_id
      Position.joins(:person_position)
              .where(active: true, mvr_eligible: true)
              .select("position.title", "person_position.person_id AS person_id")
              .order(:title)
              .group_by { |position| position.person_id.to_i }
              .transform_values { |positions| positions.map(&:title) }
    end

    # Distinct positions the person signed up for a shift in this year, where the
    # position itself carries the eligibility flag -- the personal vehicle side.
    # Someone holding an eligible position but never signing up for one of its
    # shifts is NOT listed: upstream reports on sign-ups here, which is why this
    # cannot reuse Position.vehicle_eligible_for_person (that one reads held
    # positions).
    def signup_positions_by_person_id(year, flag)
      eligible_signups(year, flag)
        .select("person_slot.person_id AS person_id", "position.title AS position_title")
        .distinct
        .order("position.title")
        .group_by { |row| row.person_id.to_i }
        .transform_values { |rows| rows.map(&:position_title) }
    end

    # Individual shifts in sign-up-eligible positions -- Intercept and friends,
    # where the shift itself is what makes the person eligible. Ordered by start
    # time; upstream leaves them in whatever order the database returned.
    def signups_by_person_id(year)
      eligible_signups(year, :mvr_signup_eligible)
        .select("person_slot.person_id AS person_id", "slot.begins AS begins",
                "position.title AS position_title")
        .order("slot.begins")
        .group_by { |row| row.person_id.to_i }
        .transform_values do |rows|
          rows.map { |row| Signup.new(position_title: row.position_title, begins: row.begins) }
        end
    end

    def eligible_signups(year, flag)
      PersonSlot.joins(slot: :position)
                .where(slot: { begins_year: year, active: true })
                .where(position: { active: true, flag => true })
    end

    # Upstream only reads person_event rows where at least one of the four flags
    # is set, which is also what puts a person in the report on flags alone.
    # signed_personal_vehicle_agreement is read for the PVR Approval column but
    # is deliberately NOT one of them: signing the agreement is not by itself a
    # reason to be on a report about who may request a vehicle.
    def event_flags_by_person_id(year)
      base = PersonEvent.where(year: year)

      base.where(signed_motorpool_agreement: true)
          .or(base.where(org_vehicle_insurance: true))
          .or(base.where(mvr_eligible: true))
          .or(base.where(may_request_stickers: true))
          .index_by(&:person_id)
    end

    def filter(rows, filters)
      rows = filter_flags(rows, filters)
      rows = filter_lists(rows, filters)
      filter_callsign(rows, filters[:callsign])
    end

    # "approved"/"eligible" keep the rows the predicate is true for;
    # "not_approved"/"not_eligible" keep the rest.
    def filter_flags(rows, filters)
      FLAG_FILTERS.reduce(rows) do |kept, (key, predicate)|
        value = filters[key]
        next kept unless active?(value)

        wanted = [APPROVED, ELIGIBLE].include?(value)
        kept.select { |row| row.public_send(predicate) == wanted }
      end
    end

    def filter_lists(rows, filters)
      LIST_FILTERS.reduce(rows) do |kept, (key, collection)|
        title = filters[key]
        next kept unless active?(title)

        kept.select { |row| row.public_send(collection).include?(title) }
      end
    end

    def filter_callsign(rows, callsign)
      return rows if callsign.blank?

      needle = callsign.downcase
      rows.select { |row| row.callsign.to_s.downcase.include?(needle) }
    end

    # The "all" sentinel is present?, so compact_blank does not drop it;
    # comparing it straight against a value would match nothing and silently
    # empty the table.
    def active?(value) = value.present? && value != ALL
  end
end
