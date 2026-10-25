# frozen_string_literal: true

module TeamsPositions::TeamRecordsHelper
  ScrollItem = Struct.new(:id, :title)

  ACTIVE_LABELS = {
    "active" => "Active",
    "inactive" => "Inactive"
  }.freeze

  # One entry per attribute chip the table draws, in both polarities, worded so
  # the option reads as a sentence about the team rather than as a column name.
  ATTRIBUTE_LABELS = {
    "mvr-eligible" => "Grants Motor Vehicle Record eligibility",
    "mvr-ineligible" => "No Motor Vehicle Record eligibility",
    "pvr-eligible" => "Grants personal vehicle eligibility",
    "pvr-ineligible" => "No personal vehicle eligibility",
    "awards-eligible" => "Awards may be granted",
    "awards-ineligible" => "No awards may be granted",
    "in-directory" => "Listed in the directory",
    "not-in-directory" => "Not listed in the directory"
  }.freeze

  # The two role-grant choices that are not a role id. Defined here rather than
  # on the controller because a helper constant that names a controller constant
  # is resolved at load time, and that deadlocks both autoloads. The controller
  # reads these at request time instead.
  ROLE_ANY = "any"
  ROLE_NONE = "none"

  ROLE_SENTINEL_LABELS = {
    ROLE_ANY => "Grants any permission",
    ROLE_NONE => "Grants no permissions"
  }.freeze

  FILTER_CHIP_LABELS = {
    type: "Type",
    active: "Status",
    attribute: "Attribute",
    role: "Role grant"
  }.freeze

  # A team's type as a reader sees it. The labels live beside the validator's
  # list of allowed types in TeamManagement; a type the Laravel app writes but
  # this list does not name still gets a readable name rather than vanishing.
  def team_record_type_label(type)
    TeamManagement::TYPE_LABELS[type] || type.to_s.titleize
  end

  # The flags listed in the Attributes column. Named in full rather than as
  # MVR/PVR: the abbreviations are jargon outside the vehicle pages.
  def team_record_attribute_labels(team)
    labels = []
    labels << "Motor Vehicle Record" if team.mvr_eligible
    labels << "Personal vehicle" if team.pvr_eligible
    labels << "Awards" if team.awards_eligible
    # Whether the team IS in the directory, not whether the override was
    # ticked -- cadres and delegations are listed by type, so asking the
    # column alone reports the great majority of directory teams as absent.
    labels << "Directory" if TeamManagement.directory_listed?(team)
    labels
  end

  def team_record_scroll_items(teams)
    teams.map { |team| ScrollItem.new("team-#{team.id}", team.title) }
  end

  # One removable chip per applied filter; each URL drops just that filter.
  def team_record_filter_chips(filter_params)
    active = UiComponents::FilterBarHelper.active_filters(filter_params)

    filter_chips(active, FILTER_CHIP_LABELS,
                 value_label: ->(key, value) { team_record_filter_value_label(key, value) }) do |remaining, _key|
      teams_positions_team_records_path(remaining)
    end
  end

  # Options for the type select, each carrying how many teams it holds, so a
  # choice promises what it will deliver.
  def team_record_type_options(type_counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      TeamManagement::TYPE_LABELS.map { |type, label| ["#{label.pluralize} (#{type_counts[type].to_i})", type] }
  end

  def team_record_active_options
    team_record_filter_options(ACTIVE_LABELS)
  end

  def team_record_attribute_options
    team_record_filter_options(ATTRIBUTE_LABELS)
  end

  # Only roles some team actually grants are offered, so no choice can lead to a
  # guaranteed-empty list. The two sentinels sit above them.
  def team_record_role_options(granted_roles)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      ROLE_SENTINEL_LABELS.map { |value, label| [label, value] } +
      granted_roles.map { |role| [role.title, role.id.to_s] }
  end

  # The delete confirmation has to name what else goes with the team, because
  # nothing here is recoverable. Deleted and released are kept in separate
  # sentences: one list of things that go away, one of things that survive.
  def team_record_delete_message(team, member_count, position_count, award_count, manager_count = 0)
    deleted = ["its membership history"]
    deleted.unshift(pluralize(member_count, "member")) if member_count.positive?
    deleted << pluralize(manager_count, "manager") if manager_count.positive?
    deleted << "#{pluralize(award_count, "award")} (and the service years they count for)" if award_count.positive?

    message = +"Delete #{team.title}? This also deletes #{deleted.to_sentence}."
    message << " Its #{pluralize(position_count, "position")} will be released, not deleted." if position_count.positive?
    message << " This cannot be undone."
  end

  private

  def team_record_filter_options(labels)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + labels.map { |value, label| [label, value] }
  end

  def team_record_filter_value_label(key, value)
    case key
    when :type then team_record_type_label(value)
    when :active then ACTIVE_LABELS[value] || value
    when :attribute then ATTRIBUTE_LABELS[value] || value
    when :role then team_record_role_label(value)
    else value
    end
  end

  # A chip has to name the role, not its id. A role deleted while a bookmark
  # still points at it falls back to the id so the chip stays removable.
  def team_record_role_label(value)
    ROLE_SENTINEL_LABELS[value] || Role.find_by(id: value)&.title || "Role ##{value}"
  end
end
