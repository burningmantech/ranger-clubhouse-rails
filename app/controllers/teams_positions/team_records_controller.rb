# frozen_string_literal: true

class TeamsPositions::TeamRecordsController < ApplicationController
  layout "teams_positions"

  # Ember gated the page at Admin alone, but the API's TeamPolicy#before admits
  # Tech Ninja to every action, and only a Tech Ninja may change role grants.
  # The API is the authority.
  authorize_role [Role::ADMIN, Role::TECH_NINJA],
                 message: "Admin or Tech Ninja role required to manage team records."

  before_action :set_team, only: %i[edit update destroy]

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # Filters are spelled here rather than read straight from params so a
  # hand-edited URL cannot widen the query, and so the chip helper and the
  # query agree on what "active" means.
  ACTIVE_FILTERS = {
    "active" => true,
    "inactive" => false
  }.freeze

  # One filter per attribute chip the table draws, in both polarities. This
  # subsumes the vehicle-only filter Ember had: two overlapping selects could be
  # set to contradict each other (not MVR-eligible AND MVR-eligible) and return
  # nothing with no hint why.
  ATTRIBUTE_FILTERS = {
    "mvr-eligible" => { mvr_eligible: true },
    "mvr-ineligible" => { mvr_eligible: false },
    "pvr-eligible" => { pvr_eligible: true },
    "pvr-ineligible" => { pvr_eligible: false },
    "awards-eligible" => { awards_eligible: true },
    "awards-ineligible" => { awards_eligible: false },
    "in-directory" => { include_in_directory: true },
    "not-in-directory" => { include_in_directory: false }
  }.freeze

  # The role-grant sentinels ("any"/"none", anything else being a role id) live
  # on TeamsPositions::TeamRecordsHelper, which owns their labels, and are read
  # inside methods rather than aliased into a constant here -- a class-body
  # constant reference resolves at load time, and a helper/controller pair that
  # names each other that way deadlocks both autoloads.

  def index
    teams = Team.order(:title)

    @total_count = teams.count
    # reorder(nil): the index's ORDER BY is meaningless on a grouped count and
    # is rejected outright under ONLY_FULL_GROUP_BY.
    @type_counts = teams.reorder(nil).group(:type).count
    @inactive_count = teams.where(active: false).count

    @filter_params = filter_params
    @return_params = current_index_params
    @granted_roles = Role.where(id: granted_role_ids).order(:title)
    @teams = apply_filters(teams).to_a
    # The type select's counts must promise what choosing a type delivers, so
    # they are narrowed by the OTHER filters -- but never by type itself, or
    # every unchosen type would read zero. With no other filter set those are
    # the counts already in hand, which is the common case.
    @matching_type_counts = if other_filters_applied?
                              apply_filters(teams, except: :type).reorder(nil).group(:type).count
                            else
                              @type_counts
                            end

    team_ids = @teams.map(&:id)
    @roles_by_team = TeamRole.where(team_id: team_ids)
                             .joins(:role)
                             .pluck(:team_id, "role.title")
                             .group_by(&:first)
                             .transform_values { |rows| rows.map(&:last).sort }
    @managers_by_team = TeamManager.where(team_id: team_ids)
                                   .includes(:person)
                                   .group_by(&:team_id)
                                   .transform_values { |rows| rows.sort_by { |row| row.person&.callsign.to_s } }
  end

  def new
    @team = Team.new(active: true, type: Team::TYPE_TEAM)
    load_form_collections
  end

  def create
    @team = Team.new(team_params)
    save_team(:new, "The team has been created.")
  end

  def edit
    load_form_collections
  end

  def update
    @team.assign_attributes(team_params)
    save_team(:edit, "The team has been updated.")
  end

  # Releases the team's positions and removes its memberships -- see
  # TeamManagement.destroy. The edit page warns with the membership count first.
  def destroy
    title = @team.title
    TeamManagement.destroy(@team)

    redirect_to teams_positions_team_records_path(current_index_params),
                success: "#{title} deleted."
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def save_team(template, message)
    role_ids = submitted_role_ids

    if role_ids == :invalid
      @team.errors.add(:role_ids, "The role grants were not submitted correctly.")
    elsif TeamManagement.save(@team, role_ids:, is_tech_ninja: tech_ninja?)
      return redirect_to team_anchor_path(@team), success: message
    end

    load_form_collections
    render template, status: :unprocessable_entity
  end

  # Values are normalized to ALL unless they name a filter this page applies.
  # Anything else -- a stale bookmark, a typo, a nested hash -- would otherwise
  # narrow nothing while still drawing a chip that claims it did, and a hash
  # would crash the chip's URL builder.
  def filter_params
    {
      type: UiComponents::FilterBarHelper.known_filter(params[:type], TeamManagement::TYPES),
      active: UiComponents::FilterBarHelper.known_filter(params[:active], ACTIVE_FILTERS.keys),
      attribute: UiComponents::FilterBarHelper.known_filter(params[:attribute], ATTRIBUTE_FILTERS.keys),
      role: UiComponents::FilterBarHelper.known_filter(params[:role], role_filter_values)
    }
  end

  # Only the roles some team actually grants are offered, so no choice can lead
  # to a guaranteed-empty list. Memoized: the select and the query both ask.
  def granted_role_ids
    @granted_role_ids ||= TeamRole.distinct.pluck(:role_id)
  end

  def role_filter_values
    TeamsPositions::TeamRecordsHelper::ROLE_SENTINEL_LABELS.keys + granted_role_ids.map(&:to_s)
  end

  def other_filters_applied?
    @filter_params.except(:type).any? { |_key, value| value != ALL }
  end

  def apply_filters(teams, except: nil)
    filters = @filter_params

    teams = teams.where(type: filters[:type]) if filters[:type] != ALL && except != :type
    teams = teams.where(active: ACTIVE_FILTERS[filters[:active]]) if filters[:active] != ALL && except != :active
    teams = teams.where(ATTRIBUTE_FILTERS[filters[:attribute]]) if filters[:attribute] != ALL && except != :attribute
    teams = apply_role_filter(teams, filters[:role]) if filters[:role] != ALL && except != :role
    teams
  end

  # A subquery rather than a join: joining team_role would return one row per
  # grant, so a team granting three roles would appear three times.
  def apply_role_filter(teams, role)
    granted = TeamRole.select(:team_id)

    case role
    when TeamsPositions::TeamRecordsHelper::ROLE_ANY then teams.where(id: granted)
    when TeamsPositions::TeamRecordsHelper::ROLE_NONE then teams.where.not(id: granted)
    else teams.where(id: granted.where(role_id: role.to_i))
    end
  end

  def load_form_collections
    @type_options = TeamManagement::TYPE_LABELS.invert.to_a
    @roles = Role.order(:title)
    @is_tech_ninja = tech_ninja?
    # Only an actor who may change grants gets their submission echoed back.
    # Otherwise a rejected form would show the read-only panel whatever grants
    # were posted -- inventing ones the team lacks and hiding the real ones,
    # under a callout saying only the Tech Team can change them.
    submitted = submitted_role_ids if @is_tech_ninja
    @role_ids = submitted.is_a?(Array) ? submitted : current_role_ids
    @member_count = team_child_count(PersonTeam)
    @position_count = team_child_count(Position)
    @award_count = team_child_count(PersonAward)
    @manager_count = team_child_count(TeamManager)
    @return_params = current_index_params
    @cancel_path = teams_positions_team_records_path(@return_params)
  end

  # The filter the reader was working in, carried through the form so saving or
  # cancelling returns them to the list they came from rather than to all 64
  # teams.
  def current_index_params
    UiComponents::FilterBarHelper.active_filters(filter_params).compact_blank
  end

  def team_child_count(model)
    @team.persisted? ? model.where(team_id: @team.id).count : 0
  end

  def current_role_ids
    return [] unless @team.persisted?

    TeamRole.find_all_for_team(@team.id).pluck(:role_id)
  end

  # Three states, because collapsing any two of them loses information the
  # caller needs:
  #
  #   nil      -- the form never offered the field (a non-Tech-Ninja edit), so
  #               the team's existing grants must be left exactly as they are
  #   []       -- a Tech Ninja cleared every box: revoke everything
  #   :invalid -- something was posted that is not a list of role ids. Reading
  #               that as either of the above would silently revoke or silently
  #               ignore, so it is reported instead.
  def submitted_role_ids
    return @submitted_role_ids if defined?(@submitted_role_ids)

    @submitted_role_ids = parse_role_ids
  end

  def parse_role_ids
    team = params[:team]
    return nil unless team.is_a?(ActionController::Parameters) && team.key?(:role_ids)

    raw = team[:role_ids]
    return :invalid unless IdList.clean?(raw)

    IdList.parse(raw)
  end

  def tech_ninja?
    Current.person&.has_role?(Role::TECH_NINJA)
  end

  def team_params
    params.expect(team: [:title, :type, :email, :resource_tag, :description,
                         :active, :mvr_eligible, :pvr_eligible,
                         :awards_eligible, :include_in_directory])
  end

  def team_anchor_path(team)
    teams_positions_team_records_path(**current_index_params, anchor: "team-#{team.id}")
  end
end
