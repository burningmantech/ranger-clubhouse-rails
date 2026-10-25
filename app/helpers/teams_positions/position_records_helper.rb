# frozen_string_literal: true

module TeamsPositions::PositionRecordsHelper
  ScrollItem = Struct.new(:id, :title)

  # Every attribute the table lists and the filter offers, in the order the
  # Ember page listed them. Worded as short statements about the position
  # rather than as column names, and without the abbreviations and internal
  # vocabulary the upstream sentences carried.
  ATTRIBUTE_LABELS = {
    all_rangers: "Granted to all Rangers",
    new_user_eligible: "Granted to new accounts",
    count_hours: "Hours count for appreciations",
    awards_eligible: "Awards may be granted",
    prevent_multiple_enrollments: "Multiple enrollments prevented",
    on_sl_report: "On the Shift Lead Report",
    on_trainer_report: "On the Trainer's Report",
    has_online_course: "Has an online course",
    has_art_mentoring: "Has ART mentoring",
    is_art_mentor: "Its team's ART mentor position",
    is_art_mentee: "Its team's ART mentee position",
    require_training_for_roles: "ART must be passed before permissions are granted",
    require_signin_for_roles: "Permissions only while signed in",
    no_training_required: "In-Person training not needed to check in",
    # "work" is not Clubhouse vocabulary -- upstream's wording is reset to the
    # verb the rest of the app uses.
    allow_echelon: "Echelon may ranger it without training",
    is_checkin_time_restricted: "No early or late check-in",
    not_timesheet_eligible: "Scheduling only -- no timesheet entries",
    auto_sign_out: "Signs people out at the hour cap",
    mvr_eligible: "Grants Motor Vehicle Record eligibility",
    mvr_signup_eligible: "Grants Motor Vehicle Record eligibility on sign-up",
    pvr_eligible: "Grants personal vehicle eligibility",
    cruise_direction: "Selectable on Cruise Direction",
    alert_when_no_trainers: "Emails when trainers are missing",
    alert_when_becomes_empty: "Emails when sign-ups empty",
    deselect_on_team_join: "Recommended for deselection on joining the team",
    no_payroll_hours_adjustment: "Hours not adjusted for payroll"
  }.freeze

  # Not a boolean column, so it is filtered on presence and listed with its
  # value rather than as a bare statement.
  PAYCODE_FILTER = "paycode"

  ACTIVE_LABELS = {
    "active" => "Active",
    "inactive" => "Inactive"
  }.freeze

  TEAM_CATEGORY_LABELS = {
    Position::TEAM_CATEGORY_ALL_MEMBERS => "Recommended to all new and existing members",
    Position::TEAM_CATEGORY_OPTIONAL => "Optional -- membership required",
    Position::TEAM_CATEGORY_PUBLIC => "Public -- available to anyone"
  }.freeze

  # The filter values that are not an id. Defined here rather than on the
  # controller because a controller constant naming a helper constant is
  # resolved at load time, and that deadlocks both autoloads. The controller
  # reads these inside methods instead.
  ROLE_ANY = "any"
  ROLE_NONE = "none"
  TEAM_NONE = "none"

  ROLE_SENTINEL_LABELS = {
    ROLE_ANY => "Grants any permission",
    ROLE_NONE => "Grants no permissions"
  }.freeze

  FILTER_CHIP_LABELS = {
    type: "Type",
    active: "Status",
    team: "Team",
    attribute: "Attribute",
    role: "Permission grant"
  }.freeze

  # The filter key for an attribute. One spelling, used by the controller to
  # build its query and by the select to build its options, so the two cannot
  # drift.
  def self.attribute_filter_key(attribute)
    attribute.to_s.dasherize
  end

  # {filter key => attribute} for every attribute the select offers, plus
  # paycode. Choosing one narrows to the positions that carry it.
  def self.attribute_filters
    @attribute_filters ||= (ATTRIBUTE_LABELS.keys + [PAYCODE_FILTER.to_sym])
                           .index_by { |attribute| attribute_filter_key(attribute) }
                           .freeze
  end

  # The attributes the position actually carries, for the table's Attributes
  # column. Upstream listed the same flags one per line.
  def position_record_attribute_labels(position)
    labels = ATTRIBUTE_LABELS.filter_map { |attribute, label| label if position[attribute] }
    labels << "Paycode #{position.paycode}" if position.paycode.present?
    labels
  end

  # A plain admin may change which training a position points at, but not remove
  # it, so the "None" option is withheld rather than offered and then rejected.
  def position_record_training_field_options(locked)
    return { label: "Training position", include_blank: "None",
             help_text: "Ignored for positions of type Training." } unless locked

    { label: "Training position",
      help_text: "Required while this position's permissions wait on a training pass. " \
                 "Only the Tech Team can lift that." }
  end

  # The links the position carries to other positions, listed above its flags
  # so the reader sees what it depends on before what it does.
  def position_record_link_labels(position, titles)
    labels = []
    labels << "Training: #{titles[position.training_position_id]}" if position.training_position_id
    labels << "Parent: #{titles[position.parent_position_id]}" if position.parent_position_id
    labels
  end

  def position_record_type_label(type)
    type.presence || "No type"
  end

  # "1-10 per slot", or whichever half of the range is set.
  #
  # Zero means unset, not a real bound: min is NOT NULL default 0 and max is
  # left at 0 by every writer that does not care, which is 180 of the 221 live
  # positions. Read literally that renders "1-0 per slot" -- a backwards range
  # -- on most of the table.
  def position_record_slot_range(position)
    min = position.min.to_i.positive? ? position.min : nil
    max = position.max.to_i.positive? ? position.max : nil

    return nil if min.nil? && max.nil?
    return "#{min} per slot" if min == max
    return "#{min}-#{max} per slot" if min && max

    min ? "#{min} or more per slot" : "up to #{max} per slot"
  end

  def position_record_scroll_items(positions)
    positions.map { |position| ScrollItem.new("position-#{position.id}", position.title) }
  end

  # One removable chip per applied filter; each URL drops just that filter.
  def position_record_filter_chips(filter_params, teams_by_id)
    active = UiComponents::FilterBarHelper.active_filters(filter_params)

    filter_chips(active, FILTER_CHIP_LABELS,
                 value_label: ->(key, value) { position_record_filter_value_label(key, value, teams_by_id) }) do |remaining, _key|
      teams_positions_position_records_path(remaining)
    end
  end

  # Options carrying how many positions each type holds, so a choice promises
  # what it will deliver.
  def position_record_type_options(type_counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      Position::TYPES.map { |type| ["#{type} (#{type_counts[type].to_i})", type] }
  end

  def position_record_active_options
    position_record_filter_options(ACTIVE_LABELS)
  end

  # Only teams that actually hold a position are offered, so no choice can
  # lead to a guaranteed-empty list. "No team" sits above them: 7 of the 221
  # positions belong to none, and they are otherwise unreachable.
  def position_record_team_options(teams, no_team_count)
    options = [UiComponents::FilterBarHelper::ALL_FILTER_OPTION]
    options << ["No team (#{no_team_count})", TEAM_NONE] if no_team_count.positive?
    options + teams.map { |team| [team.title, team.id.to_s] }
  end

  # One flat option per attribute, in the order the table lists them. Choosing
  # one narrows to the positions carrying it.
  def position_record_attribute_options
    options = ATTRIBUTE_LABELS.map do |attribute, label|
      [label, TeamsPositions::PositionRecordsHelper.attribute_filter_key(attribute)]
    end
    options << ["Has a paycode", TeamsPositions::PositionRecordsHelper.attribute_filter_key(PAYCODE_FILTER)]

    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + options
  end

  # Only roles some position actually grants are offered. The two sentinels
  # sit above them.
  def position_record_role_options(granted_roles)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      ROLE_SENTINEL_LABELS.map { |value, label| [label, value] } +
      granted_roles.map { |role| [role.title, role.id.to_s] }
  end

  # The delete confirmation has to name what else goes with the position,
  # because none of it is recoverable. Deleted and released are kept in
  # separate sentences: one list of things that go away, one of things that
  # survive without it.
  def position_record_delete_message(position, counts)
    deleted = []
    deleted << position_record_shift_phrase(counts) if counts[:slot_count].positive?
    deleted << "the grants held by #{pluralize(counts[:grant_count], "person")}" if counts[:grant_count].positive?
    deleted << "#{pluralize(counts[:award_count], "award")} (and the service years they count for)" if counts[:award_count].positive?

    released = position_record_released_sentence(counts)
    shift_coverage = position_record_shift_coverage_sentence(counts)

    message = +"Delete #{position.title}?"
    message << " This also deletes #{deleted.to_sentence}." if deleted.any?
    message << " It is also taken out of its position lineup." if counts[:lineup_count].positive?
    message << " #{shift_coverage}" if shift_coverage
    message << " #{released}" if released
    message << " This cannot be undone."
  end

  # Why a position cannot be deleted, for the panel that stands in for the
  # delete button.
  def position_record_undeletable_message(counts)
    "This position has #{pluralize(counts[:timesheet_count], "timesheet entry")} against it. " \
      "Deleting it would erase service history, so it can only be marked inactive."
  end

  private

  # Everything hanging off the position's shifts that goes with them. Joined
  # with commas rather than to_sentence: the outer list joins with "and" too,
  # and the two together read as one run-on.
  def position_record_shift_phrase(counts)
    attached = []
    attached << pluralize(counts[:signup_count], "sign-up") if counts[:signup_count].positive?
    attached << "the training records of #{pluralize(counts[:trainee_count], "trainee")}" if counts[:trainee_count].positive?
    attached << pluralize(counts[:trainer_count], "trainer record") if counts[:trainer_count].positive?

    shifts = pluralize(counts[:slot_count], "shift")
    attached.any? ? "#{shifts} (carrying #{attached.join(", ")})" : shifts
  end

  # The Shift Coverage lists the position is struck from, or nil.
  def position_record_shift_coverage_sentence(counts)
    lists = []
    lists << pluralize(counts[:shift_coverage_type_count], "shift type") if counts[:shift_coverage_type_count].positive?
    lists << pluralize(counts[:shift_coverage_post_count], "post") if counts[:shift_coverage_post_count].positive?
    "It is also taken out of #{lists.to_sentence} in Shift Coverage." if lists.any?
  end

  def position_record_released_sentence(counts)
    released = []
    released << pluralize(counts[:child_count], "child position") if counts[:child_count].positive?
    if counts[:trained_count].positive?
      released << "#{pluralize(counts[:trained_count], "position")} trained by it (whose training requirement is dropped)"
    end
    return nil if released.empty?

    "Its #{released.to_sentence} will be released, not deleted."
  end

  def position_record_filter_options(labels)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + labels.map { |value, label| [label, value] }
  end

  def position_record_filter_value_label(key, value, teams_by_id)
    case key
    when :type then position_record_type_label(value)
    when :active then ACTIVE_LABELS[value] || value
    when :team then position_record_team_label(value, teams_by_id)
    when :attribute then position_record_attribute_filter_label(value)
    when :role then position_record_role_label(value)
    else value
    end
  end

  def position_record_team_label(value, teams_by_id)
    return "No team" if value == TEAM_NONE

    teams_by_id[value.to_i]&.title || "Team ##{value}"
  end

  def position_record_attribute_filter_label(value)
    attribute = TeamsPositions::PositionRecordsHelper.attribute_filters[value]
    return value unless attribute

    attribute == PAYCODE_FILTER.to_sym ? "Has a paycode" : ATTRIBUTE_LABELS[attribute]
  end

  # A chip has to name the role, not its id. A role deleted while a bookmark
  # still points at it falls back to the id so the chip stays removable.
  def position_record_role_label(value)
    ROLE_SENTINEL_LABELS[value] || Role.find_by(id: value)&.title || "Role ##{value}"
  end
end
