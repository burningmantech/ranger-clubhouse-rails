# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength

# Prepare the membership editor data for the person management view.
class PersonMembershipPresenter
  ScrollItem = Struct.new(:id, :title, keyword_init: true)

  PositionItem = Struct.new(
    :id,
    :title,
    :active,
    :selected,
    :all_rangers,
    :new_user_eligible,
    :deselect_on_team_join,
    :permission_titles,
    :dangerous_permissions,
    keyword_init: true
  ) do
    def permissions?
      permission_titles.any?
    end

    def permission_count
      permission_titles.size
    end

    def dangerous?
      dangerous_permissions.any?
    end
  end

  TeamItem = Struct.new(
    :id,
    :title,
    :type,
    :active,
    :selected,
    :manager_selected,
    :permission_titles,
    :dangerous_permissions,
    :all_member_positions,
    :optional_positions,
    :public_positions,
    keyword_init: true
  ) do
    def permissions?
      permission_titles.any?
    end

    def permission_count
      permission_titles.size
    end

    def dangerous?
      dangerous_permissions.any?
    end

    def any_positions?
      all_member_positions.any? || optional_positions.any? || public_positions.any?
    end

    def type_label
      type.to_s.titleize
    end

    def manager_hint
      if type == Team::TYPE_TEAM
        "Allow this person to manage membership and positions for #{title}."
      else
        "Allow this person to manage membership and positions for #{title}. " \
          "Cadre and delegation manager access should be granted sparingly."
      end
    end
  end

  attr_reader :general_positions,
              :person,
              :selected_manager_ids,
              :selected_position_ids,
              :selected_team_ids,
              :team_items

  def initialize(person:,
                 viewer:,
                 selected_team_ids: nil,
                 selected_manager_ids: nil,
                 selected_position_ids: nil)
    @person = person
    @viewer = viewer

    membership = Membership.retrieve_for_person(person)

    @selected_team_ids = selected_team_ids || membership.teams.map(&:id)
    @selected_manager_ids = selected_manager_ids ||
                            TeamManager.find_for_person(person.id).pluck(:team_id)
    @selected_position_ids = selected_position_ids || membership.positions.map(&:id)

    build_collections
  end

  def admin_view?
    @admin_view ||= @viewer.has_role?(Role::ADMIN)
  end

  def can_manage_general_positions?
    admin_view?
  end

  def any_editable_items?
    general_positions.any? || team_items.any?
  end

  def show_scroll_list?
    team_items.many?
  end

  def scroll_items
    @scroll_items ||= team_items.map do |team|
      ScrollItem.new(id: "team-box-#{team.id}", title: team.title)
    end
  end

  private

  def build_collections
    manageable_team_ids = admin_view? ? nil : TeamManager.retrieve_team_ids_for_person(@viewer.id)

    teams = build_team_scope(manageable_team_ids)
    positions = build_position_scope(manageable_team_ids)

    team_role_titles = build_team_role_titles(teams.map(&:id))
    positions_by_team_id = positions.group_by(&:team_id)

    @general_positions = build_general_positions(positions)
    @team_items = build_team_items(teams, positions_by_team_id, team_role_titles)
  end

  def build_team_scope(manageable_team_ids)
    scope = Team.order(:title)
    unless admin_view?
      scope = manageable_team_ids.present? ? scope.where(id: manageable_team_ids) : Team.none
    end
    scope.to_a
  end

  def build_position_scope(manageable_team_ids)
    scope = Position.includes(:roles).order(:title)
    unless admin_view?
      scope = if manageable_team_ids.present?
                scope.where(team_id: manageable_team_ids)
              else
                Position.none
              end
    end
    scope.to_a
  end

  def build_general_positions(positions)
    return [] unless can_manage_general_positions?

    positions.filter_map do |position|
      next if position.team_id.present?
      next unless position.active || selected_position?(position.id)

      build_position_item(position)
    end
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def build_team_items(teams, positions_by_team_id, team_role_titles)
    teams.filter_map do |team|
      grouped_positions = build_grouped_positions(positions_by_team_id[team.id] || [])

      item = TeamItem.new(
        id: team.id,
        title: team.title,
        type: team.type,
        active: team.active,
        selected: selected_team?(team.id),
        manager_selected: selected_manager?(team.id),
        permission_titles: team_role_titles.dig(team.id, :titles) || [],
        dangerous_permissions: team_role_titles.dig(team.id, :dangerous) || [],
        all_member_positions: grouped_positions[:all_members],
        optional_positions: grouped_positions[:optional],
        public_positions: grouped_positions[:public]
      )

      next unless team.active || item.selected || item.manager_selected || item.any_positions?

      item
    end
  end

  def build_grouped_positions(positions)
    grouped = {
      all_members: [],
      optional: [],
      public: []
    }

    positions.each do |position|
      next unless position.active || selected_position?(position.id)

      item = build_position_item(position)

      if position.all_rangers || position.new_user_eligible || position.team_category == Position::TEAM_CATEGORY_PUBLIC
        grouped[:public] << item
      elsif position.team_category == Position::TEAM_CATEGORY_ALL_MEMBERS
        grouped[:all_members] << item
      else
        grouped[:optional] << item
      end
    end

    grouped
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def build_position_item(position)
    permission_titles = position.roles.map(&:title).sort

    PositionItem.new(
      id: position.id,
      title: position.title,
      active: position.active,
      selected: selected_position?(position.id),
      all_rangers: position.all_rangers,
      new_user_eligible: position.new_user_eligible,
      deselect_on_team_join: position.deselect_on_team_join,
      permission_titles: permission_titles,
      dangerous_permissions: dangerous_permission_titles(position.roles)
    )
  end

  def build_team_role_titles(team_ids)
    return {} if team_ids.empty?

    TeamRole.where(team_id: team_ids).includes(:role).group_by(&:team_id).transform_values do |rows|
      roles = rows.map(&:role).sort_by(&:title)
      {
        titles: roles.map(&:title),
        dangerous: dangerous_permission_titles(roles)
      }
    end
  end

  def dangerous_permission_titles(roles)
    roles.select { |role| [Role::ADMIN, Role::TECH_NINJA].include?(role.id) }
         .map(&:title)
         .sort
  end

  def selected_team?(team_id)
    selected_team_ids.include?(team_id)
  end

  def selected_manager?(team_id)
    selected_manager_ids.include?(team_id)
  end

  def selected_position?(position_id)
    selected_position_ids.include?(position_id)
  end
end

# rubocop:enable Metrics/ClassLength
