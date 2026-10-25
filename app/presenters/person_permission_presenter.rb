# frozen_string_literal: true

# Prepare permission data for the person management views.
#
# The editor (role_items) mirrors the Ember permission form: one row per role,
# showing whether the person holds it directly (checkbox) and which teams /
# positions already grant it indirectly.
#
# The person page (overview_rows) lists every permission the person reaches by
# any path, met or not, so the page can say why a permission is or is not in
# effect. RoleManager decides what is in effect; the paths only explain it.
class PersonPermissionPresenter
  RoleItem = Struct.new(
    :id,
    :title,
    :selected,
    :team_titles,
    :position_titles,
    :disabled,
    keyword_init: true
  ) do
    def granted_elsewhere?
      team_titles.any? || position_titles.any?
    end

    def council_approval?
      id == Role::ADMIN || id == Role::VIEW_PII
    end
  end

  # One permission on the person page: whether RoleManager has it in effect,
  # every way this person holds it, and the setting holding it off, if any.
  Row = Data.define(:title, :active, :paths, :off_setting, :off_setting_label)

  # One way a person holds a permission. A position path carries the
  # conditions RoleManager#retrieve_roles puts on its permissions.
  Path = Data.define(:kind, :title, :conditions, :setting) do
    def initialize(kind:, title: nil, conditions: [], setting: nil) = super

    def confers? = conditions.all?(&:met)
  end

  # One condition on a position path, met or not, in the words the page shows.
  Condition = Data.define(:met, :text)

  PATH_ORDER = %i[manual team position conferred].freeze

  def initialize(person:, viewer_is_tech_ninja: false)
    @person = person
    @viewer_is_tech_ninja = viewer_is_tech_ninja
  end

  def role_items
    @role_items ||= Role.ordered_by_title.map do |role|
      RoleItem.new(
        id: role.id,
        title: role.title,
        selected: selected_ids.include?(role.id),
        team_titles: teams_by_role[role.id]&.map(&:last) || [],
        position_titles: positions_by_role[role.id]&.map(&:last) || [],
        disabled: role.id == Role::TECH_NINJA && !@viewer_is_tech_ninja
      )
    end
  end

  # Every permission this person reaches by any path, met or not, and every
  # permission RoleManager has in effect, so none goes unlisted.
  def overview_rows(role_manager)
    paths = Hash.new { |hash, id| hash[id] = [] }
    selected_ids.each { |id| paths[id] << Path.new(kind: :manual) }
    teams_by_role.each { |id, teams| teams.each { |(_, title)| paths[id] << Path.new(kind: :team, title:) } }
    held_positions.each do |position|
      path = position_path(position)
      position.roles.each { |role| paths[role.id] << path }
    end

    # From RoleManager's own grants, cached with the status each row shows, so a
    # conferred row never contradicts it.
    conferred = RoleManager::CONFERRED_ROLES.select do |source, (_, setting)|
      role_manager.granted_roles.include?(source) && Setting.get_value(setting)
    end
    ids = paths.keys | conferred.values.map(&:first) | role_manager.roles
    roles = Role.where(id: ids | conferred.keys).ordered_by_title.to_a
    titles = roles.to_h { |role| [role.id, role.title] }
    conferred.each { |source, (target, setting)| paths[target] << Path.new(kind: :conferred, title: titles[source], setting:) }

    roles.filter_map { |role| row(role, paths.fetch(role.id, []), role_manager) if ids.include?(role.id) }
  end

  private

  def row(role, role_paths, role_manager)
    off_setting_value = off_setting(role.id)
    off_setting_label = RoleManager::SETTING_GATES_LABELS[off_setting_value] || off_setting_value
    Row.new(title: role.title, active: role_manager.has_role?(role.id),
            paths: role_paths.sort_by { |path| [PATH_ORDER.index(path.kind), path.title.to_s] },
            off_setting: off_setting_value,
            off_setting_label:
    )
  end

  # The setting holding a permission off. RoleManager drops the permission
  # whatever else holds it, so the page names the setting whenever it applies.
  def off_setting(role_id)
    setting = RoleManager::SETTING_GATED_ROLES[role_id]
    setting if setting && !Setting.get_value(setting)
  end

  # RoleManager#retrieve_roles applies the same two conditions.
  def position_path(position)
    conditions = []
    conditions << training_condition(position) if position.require_training_for_roles
    conditions << signin_condition(position) if position.require_signin_for_roles
    Path.new(kind: :position, title: position.title, conditions:)
  end

  # Keyed on the id, as RoleManager is: a training position that is not set,
  # or no longer exists, is one nobody can pass.
  def training_condition(position)
    training_id = position.training_position_id
    return Condition.new(met: false, text: "Requires training, but no training position is set") unless training_id

    # Training.did_person_pass_for_year? also counts teaching the training.
    met = trained_for?(training_id)
    title = position.training_position&.title
    text = if title.nil?
             "Requires training, but its training position (##{training_id}) no longer exists"
           elsif met
             "Passed or taught #{title} in #{Current.year}"
           else
             "Has not passed or taught #{title} in #{Current.year}"
           end
    Condition.new(met:, text:)
  end

  # RoleManager asks only whether the newest open timesheet is for this position.
  def signin_condition(position)
    newest = on_duty_timesheet
    return Condition.new(met: false, text: "Not signed in to #{position.title}") unless newest
    return Condition.new(met: true, text: "Signed in to #{position.title}") if newest.position_id == position.id

    newest_title = newest.position&.title || "another position"
    text = if open_position_ids.include?(position.id)
             "Signed in to #{position.title}, but the newer sign-in to #{newest_title} is the one that counts"
           else
             "Signed in to #{newest_title}, not #{position.title}"
           end
    Condition.new(met: false, text:)
  end

  # Every position the person has an open timesheet for this year: normally one.
  def open_position_ids
    @open_position_ids ||= Timesheet.for_year(Current.year).for_person(@person.id).on_duty_now.pluck(:position_id)
  end

  # The positions RoleManager#retrieve_roles reads.
  def held_positions
    @held_positions ||= @person.position.active.includes(:roles, :training_position).to_a
  end

  def trained_for?(training_id)
    @trained ||= {}
    @trained.fetch(training_id) { @trained[training_id] = Training.did_person_pass_for_year?(@person, training_id, Current.year) }
  end

  def on_duty_timesheet
    return @on_duty_timesheet if defined?(@on_duty_timesheet)

    @on_duty_timesheet = Timesheet.find_person_on_duty(@person.id)
  end

  def selected_ids
    @selected_ids ||= PersonRole.find_role_ids_for_person(@person.id)
  end

  # role_id => [[role_id, team_title], ...] for the teams this person belongs to.
  def teams_by_role
    @teams_by_role ||= TeamRole.joins(:team)
                               .where(team_id: @person.team.ids)
                               .pluck(:role_id, "team.title")
                               .group_by(&:first)
  end

  # role_id => [[role_id, position_title], ...] for the active positions this
  # person holds; RoleManager#retrieve_roles ignores the rest.
  def positions_by_role
    @positions_by_role ||= PositionRole.joins(:position)
                                       .where(position_id: @person.position.active.ids)
                                       .pluck(:role_id, "position.title")
                                       .group_by(&:first)
  end
end
