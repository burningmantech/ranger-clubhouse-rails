# frozen_string_literal: true

# Builds the /vehicles/registry roster.
#
# Wraps Vehicle.find_for_query and adds the three things the Rails model port
# never picked up from upstream's findForQuery tail (Vehicle.php:185-225): the
# SAP arrival date, the PVR teams and positions, and the interleaved
# fleet-by-team / personal-by-callsign sort.
#
# The enrichment is attached to a per-row delegator rather than to Vehicle
# itself: the translation rules forbid growing existing ActiveRecord models,
# and only this page ever wants these three values.
#
# The whole year is loaded once. Filtering happens in Ruby on top of it, because
# the stat boxes describe the *unfiltered* roster and would otherwise need a
# second trip to the database.
class VehicleRegistry
  # Sentinel for "this person may arrive any time", so the lib, the helper and
  # the CSV cannot drift on the spelling.
  ARRIVAL_ANY = "any"

  # Fleet vehicles with no team assignment sort as though they were team "1A",
  # matching upstream's client-side comparator.
  UNASSIGNED_FLEET_SORT_KEY = "1A"

  # Every filter the page offers. One list, so the controller's strong params,
  # the link params and this class cannot drift apart.
  FILTER_KEYS = %i[status type number permit item sap].freeze

  SAP_PRESENT = "present"
  SAP_MISSING = "missing"

  # The item filter's values are "<column>:<value>" pairs -- one filter covering
  # five unrelated columns, because the roster shows them as one "Items" cell.
  # The column half is checked against this list before it is used to read the
  # row: it arrives from the query string.
  ITEM_COLUMNS = %w[ranger_logo fuel_chit amber_light org_vehicle_insurance
                    signed_motorpool_agreement].freeze

  # One roster row: the Vehicle plus the current-year enrichment.
  class Row < SimpleDelegator
    attr_accessor :arrival_date, :mvr_teams, :mvr_positions, :mvr_signups,
                  :pvr_teams, :pvr_positions

    def initialize(vehicle)
      super
      @mvr_teams = []
      @mvr_positions = []
      @mvr_signups = []
      @pvr_teams = []
      @pvr_positions = []
    end

    def fleet? = type == Vehicle::FLEET

    def personal? = type == Vehicle::PERSONAL

    def arrives_any_time? = arrival_date == ARRIVAL_ANY

    # Held teams and positions, plus -- for the Motor Vehicle Record only -- the
    # eligible shifts signed up for. Matching the edit page's eligibility panel,
    # which reads the same three sources and no others.
    def mvr_eligible? = mvr_teams.any? || mvr_positions.any? || mvr_signups.any?

    def pvr_eligible? = pvr_teams.any? || pvr_positions.any?

    def eligible? = mvr_eligible? || pvr_eligible?

    # Case-insensitive: fleet by team assignment, personal by callsign, in one
    # interleaved list.
    def sort_key
      name = if fleet?
               team_assignment.presence || UNASSIGNED_FLEET_SORT_KEY
             else
               person&.callsign.to_s
             end

      name.downcase
    end
  end

  # The roster plus the counts the stat boxes need. Counts always describe the
  # whole year; #rows describes what the filters left.
  Result = Struct.new(:rows, :total_count, :pending_count, :approved_count,
                      :fleet_count, :personal_count, :enriched, keyword_init: true) do
    def enriched? = enriched

    def any? = rows.any?

    def empty_year? = total_count.zero?
  end

  class << self
    # year:    event year to load
    # filters: any of FILTER_KEYS
    #   status: Vehicle::PENDING / APPROVED / REJECTED, or the "all" sentinel
    #   type:   Vehicle::FLEET / PERSONAL, or the "all" sentinel
    #   number: free text searched across permit, license plate and DPW request id
    #   permit: a Vehicle::DRIVING_STICKER_* value
    #   item:   a "<column>:<value>" pair, see ITEM_COLUMNS
    #   sap:    SAP_PRESENT / SAP_MISSING
    def for_year(year, filters = {})
      enriched = year == Current.year
      rows = Vehicle.find_for_query(event_year: year).map { |vehicle| Row.new(vehicle) }
      enrich(rows) if enriched

      Result.new(rows: filter(rows, filters, enriched:).sort_by(&:sort_key),
                 total_count: rows.size,
                 # Only personal vehicles carry a request to triage. Fleet
                 # records are force-approved on save, so a fleet row left at
                 # "pending" by an import is not something anyone can review.
                 pending_count: rows.count { |row| row.personal? && row.status == Vehicle::PENDING },
                 approved_count: rows.count { |row| row.status == Vehicle::APPROVED },
                 fleet_count: rows.count(&:fleet?),
                 personal_count: rows.count(&:personal?),
                 enriched:)
    end

    # ARRIVAL_ANY, a Date, or nil when the person has no pass on file.
    def arrival_date_for(sap)
      return nil if sap.nil?
      return ARRIVAL_ANY if sap.access_any_time?

      sap.access_date&.to_date
    end

    private

    def filter(rows, filters, enriched:)
      rows = rows.select { |row| row.status == filters[:status] } if active?(filters[:status])
      rows = rows.select { |row| row.type == filters[:type] } if active?(filters[:type])
      rows = rows.select { |row| permit_matches?(row, filters[:permit]) } if active?(filters[:permit])
      rows = rows.select { |row| item_matches?(row, filters[:item]) } if active?(filters[:item])
      # No one looked up a prior year's passes, so every row would report as
      # missing one. The panel hides the filter there; this makes a hand-typed
      # URL harmless rather than a page of confident false negatives.
      rows = rows.select { |row| sap_matches?(row, filters[:sap]) } if enriched && active?(filters[:sap])
      # `number` is deliberately NOT run through active?: it is free text, and a
      # permit or plate could legitimately read "all".
      rows = rows.select { |row| number_matches?(row, filters[:number]) } if filters[:number].present?
      rows
    end

    # Nothing is issued for a denied request -- the roster blanks its permit and
    # items cells -- so a denied row must not answer a filter for something it
    # does not show.
    def issuable?(row) = row.status != Vehicle::REJECTED

    # Matched on the label, not the stored value: the column is an enum that
    # also allows "other", which no option offers and which the roster already
    # renders as "None". Comparing raw values would leave those rows unreachable
    # from a filter whose cells read exactly like the ones it does return.
    def permit_matches?(row, permit)
      issuable?(row) && row.driving_sticker_label == Vehicle::DRIVING_STICKER_OPTIONS.rassoc(permit)&.first
    end

    def item_matches?(row, item)
      column, value = item.split(":", 2)
      return false unless ITEM_COLUMNS.include?(column)

      issuable?(row) && row[column].to_s == value
    end

    # Fleet vehicles have no owner, so neither answer applies to them -- listing
    # them under "No Setup Access Pass" would invent a gap no one can close.
    def sap_matches?(row, sap)
      return false unless row.person_id

      row.arrival_date.present? == (sap == SAP_PRESENT)
    end

    # A picklist filter is inactive when it is blank or reads as the shared "all"
    # sentinel. compact_blank does not catch the sentinel -- "all".present? is
    # true -- so comparing it straight against a column matches nothing and
    # silently empties the roster.
    def active?(value)
      value.present? && value != UiComponents::FilterBarHelper::ALL_FILTER
    end

    # Mirrors the asymmetric normalization in Vehicle.find_for_query: license
    # plates are stripped of spaces and dashes when saved, so the needle is
    # stripped too; permit and DPW numbers are matched as typed.
    def number_matches?(row, number)
      needle = number.downcase
      stripped = needle.gsub(/[\s\-]/, "")

      # A needle of nothing but separators strips to "", and String#include?("")
      # is true for every string -- the plate leg would match every plated
      # vehicle while looking like a real narrowing. Guard it; the permit and
      # DPW legs still search for the separators the reader actually typed.
      (stripped.present? && row.license_number.to_s.downcase.include?(stripped)) ||
        row.sticker_number.to_s.downcase.include?(needle) ||
        row.rental_number.to_s.downcase.include?(needle)
    end

    # Upstream computes these only for the current year (Vehicle.php:186). Rows
    # for any other year are left with arrival_date nil and empty PVR lists, and
    # the views must say "not checked" rather than "none" for them.
    def enrich(rows)
      person_ids = rows.filter_map(&:person_id).uniq
      return if person_ids.empty?

      saps = AccessDocument.find_sap_for_person_ids(person_ids)
      mvr_teams = team_titles_by_person_id(person_ids, :mvr_eligible)
      mvr_positions = position_titles_by_person_id(person_ids, :mvr_eligible)
      mvr_signups = mvr_signups_by_person_id(person_ids)
      pvr_teams = team_titles_by_person_id(person_ids, :pvr_eligible)
      pvr_positions = position_titles_by_person_id(person_ids, :pvr_eligible)

      rows.each do |row|
        next unless row.person_id

        row.arrival_date = arrival_date_for(saps[row.person_id])
        row.mvr_teams = mvr_teams[row.person_id] || []
        row.mvr_positions = mvr_positions[row.person_id] || []
        row.mvr_signups = mvr_signups[row.person_id] || []
        row.pvr_teams = pvr_teams[row.person_id] || []
        row.pvr_positions = pvr_positions[row.person_id] || []
      end
    end

    def team_titles_by_person_id(person_ids, flag)
      Team.joins(:person_team)
          .where(person_team: { person_id: person_ids })
          .where(active: true, flag => true)
          .select("team.title", "person_team.person_id AS person_id")
          .order(:title)
          .group_by { |team| team.person_id.to_i }
          .transform_values { |teams| teams.map(&:title) }
    end

    # Held positions, not sign-ups -- the same source the edit page's
    # eligibility panel reads (Position.vehicle_eligible_for_person).
    def position_titles_by_person_id(person_ids, flag)
      Position.joins(:person_position)
              .where(person_position: { person_id: person_ids })
              .where(active: true, flag => true)
              .select("position.title", "person_position.person_id AS person_id")
              .order(:title)
              .group_by { |position| position.person_id.to_i }
              .transform_values { |positions| positions.map(&:title) }
    end

    # The third way into a Motor Vehicle Record: a shift signed up for in a
    # position whose shifts confer eligibility on their own. Current year only,
    # like the rest of the enrichment.
    def mvr_signups_by_person_id(person_ids)
      PersonSlot.joins(slot: :position)
                .where(person_id: person_ids)
                .where(slot: { begins_year: Current.year, active: true })
                .where(position: { active: true, mvr_signup_eligible: true })
                .select("person_slot.person_id AS person_id", "slot.begins AS begins",
                        "slot.timezone AS timezone", "position.title AS position_title")
                .order("slot.begins")
                .group_by { |row| row.person_id.to_i }
                .transform_values do |signups|
                  signups.map { |s| VehiclePaperworkReport::Signup.new(position_title: s.position_title, begins: s.begins, timezone: s.timezone) }
                end
    end
  end
end
