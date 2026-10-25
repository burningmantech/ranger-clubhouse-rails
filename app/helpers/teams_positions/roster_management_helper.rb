# frozen_string_literal: true

module TeamsPositions
  # The roster grid's vocabulary: the view filters, the column-group headings,
  # and the three things a cell can say about a position grant.
  module RosterManagementHelper
    VIEW_NEVER_ALL = "never-all"
    VIEW_NEVER_RECOMMENDED = "never-recommended"
    VIEW_NEVER_OPTIONAL = "never-optional"

    # The four upstream views. Keys are what the URL carries; "all" is the
    # filter bar's own sentinel and draws no chip.
    #
    # The labels say "no activity on" rather than upstream's "Never Worked":
    # the filter tests any recorded year, which on a training position means a
    # session trained at or taught, not a shift rangered. Saying "rangered"
    # would promise a narrower question than the one being asked.
    VIEW_LABELS = {
      UiComponents::FilterBarHelper::ALL_FILTER => "Everyone on the roster",
      VIEW_NEVER_ALL => "No activity on any Recommended or Optional position",
      VIEW_NEVER_RECOMMENDED => "No activity on a Recommended position",
      VIEW_NEVER_OPTIONAL => "No activity on an Optional position"
    }.freeze

    # The grid's short headings for the position categories. The long-form
    # labels on the position records page describe what each category means to
    # a member; a column band has room for one word.
    CATEGORY_LABELS = {
      Position::TEAM_CATEGORY_ALL_MEMBERS => "Recommended",
      Position::TEAM_CATEGORY_OPTIONAL => "Optional",
      Position::TEAM_CATEGORY_PUBLIC => "Public"
    }.freeze

    # Each column group gets an icon as well as a heading -- the categories
    # must not be told apart by color alone.
    CATEGORY_ICONS = {
      Position::TEAM_CATEGORY_ALL_MEMBERS => "star",
      Position::TEAM_CATEGORY_OPTIONAL => "circle-dot",
      Position::TEAM_CATEGORY_PUBLIC => "globe"
    }.freeze

    # Which position categories each "never rangered" view asks about. One
    # table instead of a branch per view, and the only place a view key is
    # tied to the positions it covers.
    NEVER_CATEGORIES = {
      VIEW_NEVER_ALL => TeamMembershipReport::REVOCABLE_CATEGORIES,
      VIEW_NEVER_RECOMMENDED => [Position::TEAM_CATEGORY_ALL_MEMBERS],
      VIEW_NEVER_OPTIONAL => [Position::TEAM_CATEGORY_OPTIONAL]
    }.freeze

    # What the year in a cell means, by how the position measures activity.
    KIND_VERBS = {
      TeamMembershipReport::KIND_RANGERED => "rangered",
      TeamMembershipReport::KIND_TRAINED => "trained at",
      TeamMembershipReport::KIND_TAUGHT => "taught"
    }.freeze

    CHIP_LABELS = { view: "View", position: "Position", year: "Last Activity",
                    status: "Status", callsign: "Callsign" }.freeze

    # The year select's "no activity ever" choice. Not a year, so it cannot
    # collide with one.
    YEAR_NEVER = "never"

    # A position filter carries both the position and which way round it is
    # asked, in one value. Two selects -- a position and a holds/lacks -- could
    # be set to contradict each other, and the second would mean nothing on its
    # own; this is the same flattening the team records page uses.
    POSITION_HOLDS = "has"
    POSITION_LACKS = "lacks"

    def roster_filter_chips(team, filter_params, report)
      active = UiComponents::FilterBarHelper.active_filters(filter_params)
      label = ->(key, value) { roster_filter_value_label(key, value, report) }

      filter_chips(active, CHIP_LABELS, value_label: label) do |remaining|
        teams_positions_roster_management_team_path(team, **remaining)
      end
    end

    def roster_filter_value_label(key, value, report)
      case key
      when :view then VIEW_LABELS[value]
      when :year then value == YEAR_NEVER ? "None ever" : value
      when :position then roster_position_filter_label(value, report)
      else value
      end
    end

    # Every position, asked both ways round, grouped so the two readings never
    # sit next to each other in the list.
    def roster_position_options(report)
      [["Holds", report.columns.map { |column| [column.title, "#{POSITION_HOLDS}-#{column.id}"] }],
       ["Does not hold", report.columns.map { |column| [column.title, "#{POSITION_LACKS}-#{column.id}"] }]]
    end

    def roster_year_options(report)
      [["No activity ever", YEAR_NEVER]] + report.activity_years.map { |year| [year.to_s, year.to_s] }
    end

    # module_function so the controller can validate a submitted value against
    # the same list the select is built from.
    def position_filter_values(report)
      report.columns.flat_map { |column| ["#{POSITION_HOLDS}-#{column.id}", "#{POSITION_LACKS}-#{column.id}"] }
    end
    module_function :position_filter_values

    # @return [Array(Boolean, Integer)] whether the filter asks for holders, and
    #   the position id it asks about
    def parse_position_filter(value)
      state, id = value.to_s.split("-", 2)

      [state == POSITION_HOLDS, id.to_i]
    end
    module_function :parse_position_filter

    # Only the views this team can answer. A category with no positions makes
    # its filter vacuous -- no one has activity on a position that does not
    # exist -- so it would draw a chip, claim to narrow, and return the whole
    # roster unchanged.
    # ------------------------------------------------------ bulk actions

    def roster_action_title(action)
      case action.type
      when RosterAction::GRANT_POSITION then "Grant #{action.position.title}"
      when RosterAction::REVOKE_POSITION then "Revoke #{action.position.title}"
      else "Remove from #{action.team.title}"
      end
    end

    def roster_action_confirm_label(action)
      case action.type
      when RosterAction::GRANT_POSITION then "Grant to #{pluralize(action.changing.size, "person")}"
      when RosterAction::REVOKE_POSITION then "Revoke from #{pluralize(action.changing.size, "person")}"
      else "Remove #{pluralize(action.changing.size, "person")}"
      end
    end

    # Granting adds something and is easy to undo; the other two take something
    # away, and one of them takes several things away at once.
    def roster_action_variant(action) = action.grant? ? :primary : :error

    # The sentence the preview and the final confirmation both show. Said once
    # so the two steps cannot describe different consequences.
    def roster_action_consequence(action, team)
      case action.type
      when RosterAction::GRANT_POSITION
        "Each person gains #{action.position.title}. Existing positions and team membership are untouched."
      when RosterAction::REVOKE_POSITION
        "Each person loses #{action.position.title} and any future sign-ups for it. " \
          "Their team membership and other positions are untouched."
      else
        "Each person loses their #{team.title} membership and every Recommended and Optional " \
          "position on the team. Granted Public positions are left untouched."
      end
    end

    def roster_position_filter_label(value, report)
      holds, position_id = parse_position_filter(value)
      title = report.column(position_id)&.title || "position ##{position_id}"

      holds ? "Holds #{title}" : "Does not hold #{title}"
    end

    def roster_view_options(report)
      VIEW_LABELS.reject { |value, _label|
        NEVER_CATEGORIES[value]&.all? { |category| report.position_ids_in(category).empty? }
      }.map { |value, label| [label, value] }
    end

    # "rangered" / "trained at" / "taught", by how the position measures use.
    def roster_kind_verb(kind) = KIND_VERBS[kind]

    def roster_category_heading(category)
      safe_join([fa_icon(CATEGORY_ICONS[category], :solid), CATEGORY_LABELS[category]], " ")
    end

    # A person's overall standing: the last year they were active on any of the
    # team's positions, or a flagged "never" that the legend explains.
    def roster_last_year(person)
      year = person.last_year
      return roster_never_badge("No activity on any position on this team", :error, "ban") unless year

      tag.span(year, class: "font-semibold")
    end

    # One grid cell. The year the person last used the position leads, because
    # that is what the views filter on and what the eye sweeps a column for;
    # the grant date follows only when it is known. An absent grant is a dash,
    # so a gap in a column reads as a gap.
    #
    # Most grants predate the position log and carry no date. Saying so in
    # every cell -- 496 rows deep -- buries the years, so an unknown date is
    # simply left out and the legend explains the absence once.
    def roster_grant_cell(person, column)
      grant = person.grant(column.id)
      return NOT_GRANTED unless grant

      safe_join([roster_grant_year(grant, column), roster_granted_on(grant)].compact)
    end

    private

    # Built once: the grid is mostly gaps -- a 496-row roster runs this cell
    # some five thousand times -- and every one of them is the same markup.
    #
    # The dash carries screen-reader text rather than an aria-label, which is
    # ignored on a span: the element has no role to name.
    NOT_GRANTED = ActiveSupport::SafeBuffer.new(
      %(<span class="text-stone-subtle" aria-hidden="true">&mdash;</span>) +
      %(<span class="sr-only">Not granted</span>)
    ).freeze

    def roster_granted_on(grant)
      return nil unless grant.joined_on

      tag.div("since #{ymd_format(grant.joined_on)}",
              class: "text-sm text-stone-muted whitespace-nowrap")
    end

    def roster_grant_year(grant, column)
      verb = roster_kind_verb(column.kind)
      return roster_never_badge("Granted, never #{verb} #{column.title}", :warning, "circle-half-stroke") unless grant.year

      tag.div(grant.year, class: "font-semibold", title: "Last #{verb} in #{grant.year}")
    end

    # "NS" is the upstream shorthand, kept because the operators read the grid
    # by it. The two NS badges mean different things -- granted but idle, versus
    # nothing anywhere on the team -- so each carries its own icon: colour alone
    # cannot be the difference, and the title tooltip never reaches a touch
    # screen or a screen reader.
    def roster_never_badge(title, variant, icon)
      ui_badge("NS", variant, size: "sm", icon: icon, title: title) +
        tag.span(title, class: "sr-only")
    end
  end
end
