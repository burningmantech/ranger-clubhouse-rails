# frozen_string_literal: true

class ActionLog < ApplicationRecord
  PAGE_SIZE_DEFAULT = 50

  belongs_to :person, optional: true
  belongs_to :target_person, class_name: "Person", optional: true

  # JSON serialization for the data column
  serialize :data, coder: JSON

  # Virtual attributes for associated records (populated during queries)
  attr_accessor :browser, :slot, :enrolled_slots, :positions, :position, :roles, :role, :team, :teams

  class << self
    include Pagy::Method

    # Retrieve action log records based on the given query criteria: a page
    # of them, paged by Pagy's countless mode (a row past the page says whether
    # another follows), and the total the pager names beside it -- counted, or
    # estimated from the ids when nothing filters a table of millions of rows.
    #
    # LegacyLog.find_for_query is this query over the converted Clubhouse 1
    # log, without lastday, redact_data and the enrichment; keep the two in step.
    #
    # @return [Hash] { action_logs:, pagy:, total:, approximate_total: }
    def find_for_query(query = {}, redact_data: false, **query_kwargs)
      query = query.to_h.symbolize_keys.merge(query_kwargs)

      person_id = query[:person_id]
      target_person_id = query[:target_person_id]
      page = (query[:page] || 1).to_i
      page_size = (query[:page_size] || PAGE_SIZE_DEFAULT).to_i
      page_size = PAGE_SIZE_DEFAULT if page_size <= 0
      events = query[:events] || []
      sort = query[:sort] || "desc"
      start_time = query[:start_time]
      end_time = query[:end_time]
      last_day = query[:lastday]
      message = query[:message]

      scope = all
      all_records = true

      if person_id.present?
        all_records = false
        scope = scope.where(person_id:)
      end

      if target_person_id.present?
        all_records = false
        scope = scope.where(target_person_id:)
      end

      if events.present?
        all_records = false
        exact_events = []
        like_events = []

        events.each do |event|
          if event.include?("%")
            like_events << event
          else
            exact_events << event
          end
        end

        scope = scope.where(build_events_condition(exact_events, like_events))
      end

      if start_time.present?
        all_records = false
        scope = scope.where("created_at >= ?", start_time)
      end

      if end_time.present?
        all_records = false
        scope = scope.where("created_at <= ?", end_time)
      end

      if last_day
        all_records = false
        scope = scope.where("created_at >= ?", 24.hours.ago)
      end

      if message.present?
        all_records = false
        scope = if message.include?("%")
                  scope.where_like("message", message)
                else
                  scope.where(message:)
                end
      end

      total = calculate_total(scope, all_records)
      # Nothing to fetch: the same page, with no query for its rows.
      scope = scope.none if total.zero?

      # Results sort 'asc' or 'desc'
      sort_order = (sort == "asc") ? :asc : :desc
      scope = scope.order(created_at: sort_order, id: sort_order).includes(:person, :target_person)
      pagy, rows = pagy(:countless, scope, page: [page, 1].max, limit: page_size, request: { params: {} })

      # Batch-load related records, then enrich each row
      lookups = batch_load_lookups(rows)
      rows.each { |row| enrich_row(row, redact_data, lookups) }

      # An estimate only where the ids gave one: a search for no one has none.
      { action_logs: rows, pagy:, total:, approximate_total: all_records && total.positive? }
    end

    # Record a Clubhouse event
    def record(user, event, message, data = nil, target_person_id = nil)
      create!(
        event: event,
        person_id: user.is_a?(Numeric) ? user : user&.id,
        message: message || "",
        target_person_id: target_person_id,
        data: data,
        created_at: Current.time,
        ip: Current.ip_address,
        user_agent: Current.user_agent
      )
    end

    # Ids inside the shared `data` JSON are untyped. The Laravel writers pass
    # them straight through from request parameters, so the same key holds an
    # Integer in one year and a String in another -- every one of 2019's
    # person-slot-remove rows stores a String slot_id, while 2022 onward store
    # Integers. The lookup hashes here are keyed by Integer, so a raw read
    # resolves to nil and the row silently loses its slot, position, role, or
    # team with no error anywhere. Anything that is not a usable scalar id --
    # an Array, a Hash, a boolean, a word -- resolves to nil rather than
    # raising, so one malformed row cannot take a whole page down.
    def lookup_id(value)
      return value if value.is_a?(Integer)
      return nil unless value.is_a?(String) || value.is_a?(Numeric)

      Integer(value, exception: false)
    end

    # The slot a row names, as an Integer, or 0 when it names none. Reports scan
    # these rows in bulk, so they need the miss to be a value rather than a nil
    # check at every call site.
    def slot_id_from_data(data)
      return 0 unless data.is_a?(Hash)

      lookup_id(data["slot_id"]).to_i
    end

    private

    # Coerces an id out of `data` and adds it to a lookup set, dropping anything
    # unusable.
    def collect_id(ids, value)
      id = lookup_id(value)
      ids << id if id
    end

    def build_events_condition(exact_events, like_events)
      table = arel_table
      conditions = []

      conditions << table[:event].in(exact_events) if exact_events.present?
      like_events.each do |event|
        conditions << table[:event].matches(event)
      end

      conditions.reduce do |combined, condition|
        combined.or(condition)
      end
    end

    def calculate_total(scope, all_records)
      if all_records
        # select count(*) can be extremely slow for millions of rows,
        # fudge the total by looking at the first and last ids. Asked of the
        # scope, not the table, so a search for no one (ActionLog.none) finds none.
        first_id = scope.reorder(:id).pick(:id)
        last_id = scope.reorder(id: :desc).pick(:id)
        first_id ? (last_id - first_id) + 1 : 0
      else
        scope.count
      end
    end

    # Collect all referenced IDs from rows' data and batch-query them.
    def batch_load_lookups(rows)
      slot_ids = Set.new
      position_ids = Set.new
      role_ids = Set.new
      team_ids = Set.new

      rows.each do |row|
        data = row.data
        next if data.blank?

        collect_id(slot_ids, data["slot_id"])
        collect_id(slot_ids, data["id"]) if %w[slot-update slot-create slot-delete].include?(row.event)
        slot_ids.merge(normalize_lookup_ids(data["enrolled_slot_ids"]))

        position_ids.merge(normalize_lookup_ids(data["position_ids"]))
        collect_id(position_ids, data["position_id"])
        collect_id(position_ids, data["id"]) if %w[position-update position-create position-delete].include?(row.event)

        role_ids.merge(normalize_lookup_ids(data["role_ids"]))
        collect_id(role_ids, data["role_id"])
        collect_id(role_ids, data["id"]) if %w[role-update role-create role-delete].include?(row.event)

        team_ids.merge(normalize_lookup_ids(data["team_ids"]))
        collect_id(team_ids, data["team_id"])
        collect_id(team_ids, data["id"]) if %w[team-update team-create team-destroy team-delete].include?(row.event)
      end

      {
        slots: slot_ids.any? ? Slot.where(id: slot_ids).includes(:position).index_by(&:id) : {},
        positions: position_ids.any? ? Position.where(id: position_ids).select(:id, :title).index_by(&:id) : {},
        roles: role_ids.any? ? Role.where(id: role_ids).select(:id, :title).index_by(&:id) : {},
        teams: team_ids.any? ? Team.where(id: team_ids).select(:id, :title, :type).index_by(&:id) : {}
      }
    end

    def enrich_row(row, redact_data, lookups)
      data = row.data

      if row.user_agent.present?
        row.browser = parse_user_agent(row.user_agent)
      end

      return if data.blank?

      enrich_with_slot(row, data, lookups[:slots])
      enrich_with_positions(row, data, lookups[:positions])
      enrich_with_roles(row, data, lookups[:roles])
      enrich_with_team(row, data, lookups[:teams])

      row.data = nil if redact_data
    end

    def parse_user_agent(user_agent)
      # Basic user agent parsing - can be enhanced with a gem if needed
      platform = case user_agent
                 when /Windows/i then "Windows"
                 when /Macintosh|Mac OS/i then "macOS"
                 when /Linux/i then "Linux"
                 when /iPhone|iPad/i then "iOS"
                 when /Android/i then "Android"
                 else "Unknown"
                 end

      browser, version = case user_agent
                         when %r{Firefox/(\d+[\d.]*)}i then ["Firefox", ::Regexp.last_match(1)]
                         when %r{Edg/(\d+[\d.]*)}i then ["Edge", ::Regexp.last_match(1)]
                         when %r{Chrome/(\d+[\d.]*)}i then ["Chrome", ::Regexp.last_match(1)]
                         when %r{Safari/(\d+[\d.]*)}i then ["Safari", ::Regexp.last_match(1)]
                         else ["Unknown", nil]
                         end

      { platform: platform, browser: browser, version: version }
    end

    def enrich_with_slot(row, data, slots_by_id)
      slot_id = lookup_id(data["slot_id"])
      slot_id ||= lookup_id(data["id"]) if %w[slot-update slot-create slot-delete].include?(row.event)
      return unless slot_id

      row.slot = slots_by_id[slot_id]

      enrolled_slot_ids = normalize_lookup_ids(data["enrolled_slot_ids"])
      return if enrolled_slot_ids.empty?

      row.enrolled_slots = enrolled_slot_ids.filter_map { |id| slots_by_id[id] }
    end

    def enrich_with_positions(row, data, positions_by_id)
      position_ids = normalize_lookup_ids(data["position_ids"])
      row.positions = position_ids.filter_map { |id| positions_by_id[id] }.sort_by(&:title) if position_ids.any?

      position_id = lookup_id(data["position_id"])
      position_id ||= lookup_id(data["id"]) if %w[position-update position-create position-delete].include?(row.event)
      return unless position_id

      row.position = positions_by_id[position_id]
    end

    def enrich_with_roles(row, data, roles_by_id)
      role_ids = normalize_lookup_ids(data["role_ids"])
      row.roles = role_ids.filter_map { |id| roles_by_id[id] }.sort_by(&:title) if role_ids.any?

      role_id = lookup_id(data["role_id"])
      role_id ||= lookup_id(data["id"]) if %w[role-update role-create role-delete].include?(row.event)
      return unless role_id

      row.role = roles_by_id[role_id]
    end

    def enrich_with_team(row, data, teams_by_id)
      team_ids = normalize_lookup_ids(data["team_ids"])
      row.teams = team_ids.filter_map { |id| teams_by_id[id] }.sort_by(&:title) if team_ids.any?

      team_id = lookup_id(data["team_id"])
      team_id ||= lookup_id(data["id"]) if %w[team-update team-create team-destroy team-delete].include?(row.event)
      return unless team_id

      row.team = teams_by_id[team_id]
    end

    def normalize_lookup_ids(value)
      case value
      when Hash
        value.values.filter_map { |id| lookup_id(id) }
      when Array
        value.flat_map { |item|
          item.is_a?(Hash) ? item.values : item
        }.filter_map { |id| lookup_id(id) }
      else
        [lookup_id(value)].compact
      end
    end
  end
end
