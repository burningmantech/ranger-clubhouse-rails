# frozen_string_literal: true

class TeamsPositions::PositionRecordsController < ApplicationController
  layout "teams_positions"

  # Ember gated the page at Admin alone, but the API's PositionPolicy#before
  # admits Tech Ninja to every action, and only a Tech Ninja may change
  # permission grants. The API is the authority.
  authorize_role [Role::ADMIN, Role::TECH_NINJA],
                 message: "Admin or Tech Ninja role required to manage position records."

  before_action :set_position, only: %i[edit update destroy]

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # Filters are spelled here rather than read straight from params so a
  # hand-edited URL cannot widen the query, and so the chip helper and the
  # query agree on what "active" means.
  ACTIVE_FILTERS = {
    "active" => true,
    "inactive" => false
  }.freeze

  # The attribute filter's keys and the labels the select draws are both
  # derived from one map on TeamsPositions::PositionRecordsHelper. Read inside
  # methods, never from this class body: a controller constant naming a helper
  # constant resolves at load time and deadlocks both autoloads.

  def index
    positions = Position.order(:title)

    @total_count = positions.count
    # reorder(nil): the index's ORDER BY is meaningless on a grouped count and
    # is rejected outright under ONLY_FULL_GROUP_BY.
    @type_counts = positions.reorder(nil).group(:type).count
    @active_count = positions.where(active: true).count
    @inactive_count = @total_count - @active_count
    @granting_count = PositionRole.distinct.count(:position_id)

    @filter_params = filter_params
    @return_params = current_index_params
    @granted_roles = Role.where(id: granted_role_ids).order(:title)
    @teams = Team.where(id: team_ids_with_positions).order(:title)
    @teams_by_id = @teams.index_by(&:id)
    @no_team_count = positions.where(team_id: nil).count

    @positions = apply_filters(positions).includes(:team).to_a
    # The type select's counts must promise what choosing a type delivers, so
    # they are narrowed by the OTHER filters -- but never by type itself, or
    # every unchosen type would read zero. With no other filter set those are
    # the counts already in hand, which is the common case.
    @matching_type_counts = if other_filters_applied?
                              apply_filters(positions, except: :type).reorder(nil).group(:type).count
                            else
                              @type_counts
                            end

    load_index_associations
  end

  def new
    @position = Position.new(active: true, type: Position::TYPE_FRONTLINE, min: 1,
                             team_category: Position::TEAM_CATEGORY_PUBLIC)
    load_form_collections
  end

  def create
    @position = Position.new(position_params)
    save_position(:new, "The position has been created.")
  end

  def edit
    load_form_collections
  end

  def update
    @position.assign_attributes(position_params)
    save_position(:edit, "The position has been updated.")
  end

  # Deletes the position's shifts and sign-ups along with it -- see
  # PositionManagement.destroy. The edit page names every count first.
  #
  # The refusal path is reachable without the form: the edit page withholds the
  # delete button once a position carries service history, but a bookmarked
  # DELETE still arrives here.
  def destroy
    title = @position.title

    unless PositionManagement.destroy(@position)
      load_form_collections
      return render :edit, status: :unprocessable_entity
    end

    redirect_to teams_positions_position_records_path(current_index_params),
                success: "#{title} deleted."
  end

  private

  def set_position
    @position = Position.find(params[:id])
  end

  def save_position(template, message)
    role_ids = submitted_role_ids

    if role_ids == :invalid
      @position.errors.add(:role_ids, "The role grants were not submitted correctly.")
    elsif PositionManagement.save(@position, role_ids:, is_tech_ninja: tech_ninja?)
      return redirect_to position_anchor_path(@position), success: message
    end

    load_form_collections
    render template, status: :unprocessable_entity
  end

  # One query per column the table draws, rather than one per row.
  def load_index_associations
    position_ids = @positions.map(&:id)

    @roles_by_position = PositionRole.where(position_id: position_ids)
                                     .joins(:role)
                                     .pluck(:position_id, "role.title")
                                     .group_by(&:first)
                                     .transform_values { |rows| rows.map(&:last).sort }

    linked_ids = @positions.flat_map { |position| [position.training_position_id, position.parent_position_id] }
    @linked_titles = Position.titles_by_id(linked_ids.compact.uniq)
  end

  # Values are normalized to ALL unless they name a filter this page applies.
  # Anything else -- a stale bookmark, a typo, a nested hash -- would otherwise
  # narrow nothing while still drawing a chip that claims it did, and a hash
  # would crash the chip's URL builder.
  def filter_params
    {
      type: UiComponents::FilterBarHelper.known_filter(params[:type], Position::TYPES),
      active: UiComponents::FilterBarHelper.known_filter(params[:active], ACTIVE_FILTERS.keys),
      team: UiComponents::FilterBarHelper.known_filter(params[:team], team_filter_values),
      attribute: UiComponents::FilterBarHelper.known_filter(params[:attribute], attribute_filters.keys),
      role: UiComponents::FilterBarHelper.known_filter(params[:role], role_filter_values)
    }
  end

  def attribute_filters
    TeamsPositions::PositionRecordsHelper.attribute_filters
  end

  # Only the roles some position actually grants are offered, so no choice can
  # lead to a guaranteed-empty list. Memoized: the select and the query both ask.
  def granted_role_ids
    @granted_role_ids ||= PositionRole.distinct.pluck(:role_id)
  end

  def role_filter_values
    TeamsPositions::PositionRecordsHelper::ROLE_SENTINEL_LABELS.keys + granted_role_ids.map(&:to_s)
  end

  def team_filter_values
    [TeamsPositions::PositionRecordsHelper::TEAM_NONE] + team_ids_with_positions.map(&:to_s)
  end

  # Memoized: the team select and the filter validator both ask, and
  # filter_params runs before the select's teams are loaded.
  def team_ids_with_positions
    @team_ids_with_positions ||= Position.distinct.where.not(team_id: nil).pluck(:team_id)
  end

  def other_filters_applied?
    @filter_params.except(:type).any? { |_key, value| value != ALL }
  end

  def apply_filters(positions, except: nil)
    filters = @filter_params

    positions = positions.where(type: filters[:type]) if filters[:type] != ALL && except != :type
    positions = positions.where(active: ACTIVE_FILTERS[filters[:active]]) if filters[:active] != ALL && except != :active
    positions = apply_team_filter(positions, filters[:team]) if filters[:team] != ALL && except != :team
    positions = apply_attribute_filter(positions, filters[:attribute]) if filters[:attribute] != ALL && except != :attribute
    positions = apply_role_filter(positions, filters[:role]) if filters[:role] != ALL && except != :role
    positions
  end

  def apply_team_filter(positions, team)
    return positions.where(team_id: nil) if team == TeamsPositions::PositionRecordsHelper::TEAM_NONE

    positions.where(team_id: team.to_i)
  end

  # Narrows to the positions carrying the attribute. Only the positive
  # direction is offered, which is also what keeps this NULL-safe:
  # on_sl_report holds NULL on a third of the table, and `= TRUE` excludes
  # those rows the same way it excludes FALSE.
  def apply_attribute_filter(positions, filter)
    attribute = attribute_filters[filter]

    return positions.with_paycode if attribute.to_s == TeamsPositions::PositionRecordsHelper::PAYCODE_FILTER

    positions.where(attribute => true)
  end

  # A subquery rather than a join: joining position_role would return one row
  # per grant, so a position granting three roles would appear three times.
  def apply_role_filter(positions, role)
    granted = PositionRole.select(:position_id)

    case role
    when TeamsPositions::PositionRecordsHelper::ROLE_ANY then positions.where(id: granted)
    when TeamsPositions::PositionRecordsHelper::ROLE_NONE then positions.where.not(id: granted)
    else positions.where(id: granted.where(role_id: role.to_i))
    end
  end

  def load_form_collections
    @teams = Team.order(:title)
    @roles = Role.order(:title)
    @is_tech_ninja = tech_ninja?
    # Only an actor who may change grants gets their submission echoed back.
    # Otherwise a rejected form would show the read-only panel whatever grants
    # were posted -- inventing ones the position lacks and hiding the real
    # ones, under a callout saying only the Tech Team can change them.
    submitted = submitted_role_ids if @is_tech_ninja
    @role_ids = submitted.is_a?(Array) ? submitted : current_role_ids
    @counts = PositionManagement.child_counts(@position)
    # A plain admin may change which training a position points at, but not
    # remove it: require_training_for_roles is Tech-Ninja-only, so clearing the
    # training fails a validation naming a checkbox their form never renders,
    # and nothing on their page can resolve it.
    @training_position_locked = @position.require_training_for_roles && !@is_tech_ninja
    @training_options = training_position_options
    @parent_options = parent_position_options
    @return_params = current_index_params
    @cancel_path = teams_positions_position_records_path(@return_params)
  end

  # The positions a trainee has to pass. Trainer positions are excluded the way
  # upstream excludes them -- by title, since nothing in the schema separates a
  # trainer position from the training itself.
  def training_position_options
    options = Position.by_type(Position::TYPE_TRAINING)
                      .where.not(id: @position.id)
                      .order(:title)
                      .reject { |position| position.title.to_s.match?(/\btrainer\b/i) }
                      .map { |position| [position.title, position.id] }

    # Whatever the position already points at stays selectable even when the
    # filters above would drop it -- a rename to "... Trainer" or a type change
    # is enough. Otherwise the select renders with nothing selected and the next
    # save, for any unrelated reason, silently clears the link.
    current = @position.training_position_id
    return options if current.blank? || options.any? { |(_title, id)| id == current }

    (options << [Position.retrieve_title(current), current]).sort_by(&:first)
  end

  # Every other position: a position cannot be its own parent, and the service
  # rejects it if the form is bypassed.
  def parent_position_options
    scope = Position.order(:title)
    scope = scope.where.not(id: @position.id) if @position.persisted?
    scope.pluck(:title, :id)
  end

  # The filter the reader was working in, carried through the form so saving or
  # cancelling returns them to the list they came from rather than to all 221
  # positions.
  def current_index_params
    UiComponents::FilterBarHelper.active_filters(filter_params).compact_blank
  end

  def current_role_ids
    return [] unless @position.persisted?

    PositionRole.find_all_for_position(@position.id).pluck(:role_id)
  end

  # Three states, because collapsing any two of them loses information the
  # caller needs:
  #
  #   nil      -- the form never offered the field (a non-Tech-Ninja edit), so
  #               the position's existing grants must be left exactly as they are
  #   []       -- a Tech Ninja cleared every box: revoke everything
  #   :invalid -- something was posted that is not a list of role ids. Reading
  #               that as either of the above would silently revoke or silently
  #               ignore, so it is reported instead.
  def submitted_role_ids
    return @submitted_role_ids if defined?(@submitted_role_ids)

    @submitted_role_ids = parse_role_ids
  end

  def parse_role_ids
    position = params[:position]
    return nil unless position.is_a?(ActionController::Parameters) && position.key?(:role_ids)

    raw = position[:role_ids]
    return :invalid unless IdList.clean?(raw)

    IdList.parse(raw)
  end

  def tech_ninja?
    Current.person&.has_role?(Role::TECH_NINJA)
  end

  # These two govern how the position's permission grants behave -- whether
  # they wait on a training pass, and whether they last past sign-out. The form
  # offers them only to a Tech Ninja, so they are only accepted from one:
  # upstream leaves them mass-assignable to any admin, which lets a crafted
  # POST widen a grant without going near the grant list itself.
  GRANT_BEHAVIOR_PARAMS = %i[require_training_for_roles require_signin_for_roles].freeze

  def position_params
    permitted = params.expect(position: [
      :title, :short_title, :type, :resource_tag, :min, :max,
      :ranger_scheduling_header, :applicant_scheduling_header,
      :active, :all_rangers, :new_user_eligible, :cruise_direction,
      :team_id, :team_category, :deselect_on_team_join,
      :has_art_mentoring, :is_art_mentor, :is_art_mentee,
      :awards_eligible,
      :no_training_required, :not_timesheet_eligible, :allow_echelon, :is_checkin_time_restricted,
      :count_hours, :prevent_multiple_enrollments, :on_sl_report, :on_trainer_report, :has_online_course,
      *GRANT_BEHAVIOR_PARAMS,
      :training_position_id, :parent_position_id,
      :mvr_eligible, :pvr_eligible, :mvr_signup_eligible,
      :paycode, :no_payroll_hours_adjustment,
      :auto_sign_out, :sign_out_hour_cap,
      :alert_when_no_trainers, :alert_when_becomes_empty, :contact_email
    ])

    tech_ninja? ? permitted : permitted.except(*GRANT_BEHAVIOR_PARAMS.map(&:to_s))
  end

  def position_anchor_path(position)
    teams_positions_position_records_path(**current_index_params, anchor: "position-#{position.id}")
  end
end
