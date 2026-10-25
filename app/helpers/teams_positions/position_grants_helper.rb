# frozen_string_literal: true

module TeamsPositions::PositionGrantsHelper
  # Its own copy, the way every other page with a jump list carries one:
  # dropdown_scroll_list takes anything answering to id and title, and a
  # Position answers to both with the wrong id -- the anchor needs the row's.
  ScrollItem = Struct.new(:id, :title)

  # The filter values that are not a status or a position type. Defined here
  # rather than on the controller because a controller constant naming a helper
  # constant is resolved at load time, and that deadlocks both autoloads. The
  # controller reads these inside methods instead.
  STATUS_RANGERING = "rangering"
  ON_SITE_ONLY = "on-site"
  MATCHING_ONLY = "matching"

  FILTER_CHIP_LABELS = {
    type: "Type",
    status: "Status",
    on_site: "Location",
    matching: "Positions"
  }.freeze

  # Two of the four filters carry a value the reader did not pick by name, so
  # only those two need a phrase written for them.
  SENTINEL_LABELS = {
    STATUS_RANGERING => "Rangering statuses",
    ON_SITE_ONLY => "On site only",
    MATCHING_ONLY => "With matching people"
  }.freeze

  # Every URL this page builds carries status explicitly. An absent status param
  # means the Rangering set, so a link that simply dropped it -- the status
  # chip's "remove", or "clear all" -- would silently re-apply the filter it
  # claimed to remove. always: is what tells the shared builder that.
  def position_grants_url(filters)
    filter_url(:teams_positions_position_grants_path, filters, always: [:status])
  end

  # One removable chip per applied filter; each URL drops just that filter.
  def position_grants_filter_chips(filter_params)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: ->(key, value) { position_grants_filter_value_label(key, value) }) do |remaining|
      position_grants_url(remaining)
    end
  end

  # A value is shown exactly as the control that set it spells it: a status
  # reads as it is stored, and a type comes from a fixed list the select
  # already spells ("HQ").
  def position_grants_filter_value_label(key, value)
    SENTINEL_LABELS.fetch(value) { value }
  end

  # The A-Z jump list over the rows on screen. The ids match what the index
  # gives each drill-down row, so a jump lands on the row itself.
  def position_grants_scroll_items(positions)
    positions.map { |position| ScrollItem.new("position-#{position.id}", position.title) }
  end

  def position_grants_type_options
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + Position::TYPES.map { |type| [type, type] }
  end

  # Read off the controller's own set rather than written out beside it. The
  # hand-kept version drifted -- it named six of the eight hidden statuses, so a
  # reader who could not find an auditor had no way to tell a missing grant from
  # a hidden one.
  def position_grants_status_help
    hidden = Person::ALL_STATUSES - TeamsPositions::PositionGrantsController::RANGERING_STATUSES

    "Rangering statuses leaves out #{hidden.to_sentence} accounts."
  end

  # The Rangering set sits above the individual statuses: it is what the page
  # arrives filtered to, and the choice most readers want back after widening.
  def position_grants_status_options
    [["Rangering statuses", STATUS_RANGERING],
     ["All statuses", UiComponents::FilterBarHelper::ALL_FILTER]] +
      Person::ALL_STATUSES.map { |status| [status, status] }
  end

  def position_grants_on_site_options
    [["Everyone", UiComponents::FilterBarHelper::ALL_FILTER],
     ["On site only", ON_SITE_ONLY]]
  end

  def position_grants_matching_options
    [["All positions", UiComponents::FilterBarHelper::ALL_FILTER],
     ["Only positions with matching people", MATCHING_ONLY]]
  end

  # The one summary line above the rows, describing the rows themselves.
  # "Grants" rather than "people": somebody holding four positions is counted
  # four times here, and calling that a head count would be a lie.
  def position_grants_summary(shown:, total:, grants:, unassigned:)
    parts = ["Showing #{shown} of #{pluralize(total, "position")}",
             "#{number_with_delimiter(grants)} #{"grant".pluralize(grants)}"]
    parts << "#{number_with_delimiter(unassigned)} unassigned" if unassigned.positive?
    parts.join(" · ")
  end

  # "1,141 people · 4 on site · every Ranger expected". The on-site half is
  # dropped while the on-site filter is applied, where it could only repeat the
  # number beside it. Who is expected to hold the position rides here rather
  # than in a badge: it is a property of the position rather than something
  # wrong with it, and it is what the unassigned badge beside it is counting
  # against.
  def position_grants_row_meta(position, count, on_site_count, on_site_filtered)
    people = "#{number_with_delimiter(count)} #{"person".pluralize(count)}"
    people += " on site" if on_site_filtered
    on_site = "#{number_with_delimiter(on_site_count)} on site" if !on_site_filtered && on_site_count.positive?

    [people, on_site, position_grants_scope_phrase(position)].compact.join(" · ")
  end

  def position_grants_scope_phrase(position)
    return "every account expected" if position.new_user_eligible
    return "every Ranger expected" if position.all_rangers

    nil
  end

  # Badges name only what is wrong with the position: that it is retired, and
  # that somebody is missing a grant they are meant to hold. A badge on every
  # row is noise.
  def position_grants_row_badges(position, unassigned)
    badges = []
    badges << ui_badge("Inactive", :warning, size: "base", icon: "circle-xmark", icon_type: :solid) unless position.active
    if unassigned.positive?
      badges << ui_badge("#{number_with_delimiter(unassigned)} unassigned", :error, size: "base",
                         icon: "triangle-exclamation", icon_type: :solid)
    end
    badges
  end

  # The two flags upstream drew as "All Ranger" and "All Accounts", worded as
  # who is expected to hold the position. Both flags on one position reports the
  # wider of the two, which is the pool the unassigned list is measured against.
  def position_grants_scope_badge(position, size: "base")
    if position.new_user_eligible
      ui_badge("Every account", :primary, size:, icon: "globe", icon_type: :solid)
    elsif position.all_rangers
      ui_badge("Every Ranger", :primary, size:, icon: "universal-access", icon_type: :solid)
    end
  end

  # Says who the unassigned list was measured against, because the answer is not
  # the same for both flags and the difference decides whether a name belongs.
  # Both pools are read off the controller for the same reason as the status
  # help above: the Ranger half used to name three of its four statuses, which
  # told a reader auditing an inactive-extension row that it did not belong.
  def position_grants_unassigned_explanation(position)
    controller = TeamsPositions::PositionGrantsController

    if position.new_user_eligible
      "Every account that is not #{controller::NEW_USER_EXCLUDED.to_sentence(last_word_connector: ", or ")} " \
        "is expected to hold this position."
    else
      "Every #{controller::ALL_RANGERS_POOL.to_sentence(last_word_connector: ", or ")} Ranger " \
        "is expected to hold this position."
    end
  end
end
