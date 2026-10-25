# frozen_string_literal: true

class Person::SwagController < ApplicationController
  layout "person"

  include PersonConcern

  before_action :require_swag_manager, except: [:index]
  before_action :set_person_swag, only: [:edit, :update, :destroy]
  before_action :load_active_swags, only: [:new, :create]
  before_action :load_swags_for_edit, only: [:edit, :update]

  helper_method :swag_manager?

  NEW_SWAG_TYPES = [
    Swag::SHIRT_T_SHIRT,
    Swag::SHIRT_LONG_SLEEVE,
    Swag::TYPE_DEPT_PIN,
    Swag::TYPE_DEPT_PATCH,
    Swag::TYPE_ORG_PATCH,
    Swag::TYPE_ORG_PIN,
    Swag::TYPE_OTHER
  ].freeze

  SWAG_TITLES = {
    Swag::SHIRT_T_SHIRT => "T-Shirt",
    Swag::SHIRT_LONG_SLEEVE => "Long Sleeve Shirt",
    Swag::TYPE_DEPT_PIN => "Ranger Service Pin",
    Swag::TYPE_DEPT_PATCH => "Ranger Service Patch",
    Swag::TYPE_ORG_PATCH => "Org Service Patch",
    Swag::TYPE_ORG_PIN => "Org Service Pin",
    Swag::TYPE_OTHER => "Other Swag"
  }.freeze

  def index
    year = Current.year
    @person_swags = PersonSwag.find_for_query(person_id: @person.id)
    @timesheets = Timesheet.find_for_query(person_id: @person.id, year:)
    @summary = EventSummaryReport.execute(current_user.id, year, rows: @timesheets)
    @is_shiny_penny = Timesheet.alpha_entry?(@person.id) && @person.status == Person::ACTIVE
  end

  def new
    @swag_type    = sanitize_swag_type(params[:swag_type])
    @swag_options = build_swag_options(@swag_type)
    @swag_title   = SWAG_TITLES[@swag_type]
    @person_swag  = @person.person_swags.build(
      year_issued: Current.year,
      swag_id: default_swag_id_for(@swag_type)
    )
  end

  def create
    @swag_type    = sanitize_swag_type(params[:swag_type])
    @swag_options = build_swag_options(@swag_type)
    @swag_title   = SWAG_TITLES[@swag_type]
    @person_swag  = @person.person_swags.build(person_swag_params)

    unless selected_swag_allowed?
      @person_swag.errors.add(:swag_id, "That swag is not available for #{@swag_title}.")
      render :new, status: :unprocessable_entity
      return
    end

    if @person_swag.save
      redirect_to person_swag_index_path(@person), success: "Swag record saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    derive_swag_type_for_edit
  end

  def update
    derive_swag_type_for_edit
    @person_swag.assign_attributes(person_swag_params)

    unless selected_swag_allowed?
      @person_swag.errors.add(:swag_id, "That swag is not available for #{@swag_title}.")
      render :edit, status: :unprocessable_entity
      return
    end

    if @person_swag.save
      redirect_to person_swag_index_path(@person), success: "Swag record updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @person_swag.destroy
    redirect_to person_swag_index_path(@person), success: "Swag record deleted."
  end

  private

  def load_active_swags
    @all_swags = Swag.find_for_query(active: true)
  end

  def load_swags_for_edit
    @all_swags = Swag.find_for_query(active: true)

    if @person_swag&.swag && @all_swags.none? { |swag| swag.id == @person_swag.swag_id }
      @all_swags << @person_swag.swag
    end
  end

  def sanitize_swag_type(value)
    NEW_SWAG_TYPES.include?(value) ? value : Swag::TYPE_OTHER
  end

  def build_swag_options(swag_type)
    case swag_type
    when Swag::SHIRT_T_SHIRT
      @all_swags.select { |s| s.type == Swag::TYPE_DEPT_SHIRT && s.shirt_type == Swag::SHIRT_T_SHIRT }
    when Swag::SHIRT_LONG_SLEEVE
      @all_swags.select { |s| s.type == Swag::TYPE_DEPT_SHIRT && s.shirt_type == Swag::SHIRT_LONG_SLEEVE }
    when Swag::TYPE_DEPT_PIN   then @all_swags.select { |s| s.type == Swag::TYPE_DEPT_PIN }
    when Swag::TYPE_DEPT_PATCH then @all_swags.select { |s| s.type == Swag::TYPE_DEPT_PATCH }
    when Swag::TYPE_ORG_PATCH  then @all_swags.select { |s| s.type == Swag::TYPE_ORG_PATCH }
    when Swag::TYPE_ORG_PIN    then @all_swags.select { |s| s.type == Swag::TYPE_ORG_PIN }
    else                            @all_swags.select { |s| s.type == Swag::TYPE_OTHER }
    end
  end

  def default_swag_id_for(swag_type)
    case swag_type
    when Swag::SHIRT_T_SHIRT     then @person.tshirt_swag_id
    when Swag::SHIRT_LONG_SLEEVE then @person.long_sleeve_swag_id
    end
  end

  def derive_swag_type_for_edit
    swag = @person_swag.swag
    @swag_type = if swag&.type == Swag::TYPE_DEPT_SHIRT
                   swag.shirt_type.presence || Swag::SHIRT_T_SHIRT
                 else
                   swag&.type || Swag::TYPE_OTHER
                 end
    @swag_options = build_swag_options(@swag_type)
    @swag_title   = SWAG_TITLES[@swag_type]
  end

  def set_person_swag
    @person_swag = @person.person_swags.find(params[:id])
  end

  def person_swag_params
    params.expect(person_swag: [:swag_id, :year_issued, :notes])
  end

  def selected_swag_allowed?
    selected_id = @person_swag.swag_id.to_i
    selected_id.positive? && @swag_options.any? { |swag| swag.id == selected_id }
  end

  def swag_manager?
    Current.admin? || has_role?(Role::QUARTERMASTER)
  end


  def require_swag_manager
    return true if swag_manager?

    redirect_to person_swag_index_path(@person),
                error: "Admin or Quartermaster role required to modify swag records."
    false
  end
end
