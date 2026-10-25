# frozen_string_literal: true

class Scheduling::PositionCreditCopiesController < ApplicationController
  layout "scheduling"

  authorize_role [Role::ADMIN], message: "Admin role required to manage position credits."

  before_action :setup_year
  before_action :load_copy_state

  def new
  end

  def create
    # The "Update Preview" submit re-renders the form with the submitted
    # deltas/selections applied; nothing is copied.
    return render :new, status: :unprocessable_entity if params[:preview]

    result = Scheduling::PositionCreditCopier.copy(year: @year,
                                               ids: @selected_ids,
                                               delta: @delta,
                                               new_position_id: params[:new_position_id].presence)

    if result.success?
      redirect_to scheduling_position_credits_path(year: @year),
                  success: "#{result.credits.size} position #{"credit".pluralize(result.credits.size)} copied."
    else
      flash.now[:error] = result.errors.join(" ")
      render :new, status: :unprocessable_entity
    end
  end

  private

  # Builds everything the copy form needs, for both the initial GET and POST
  # re-renders (preview refresh / errors) where the submitted values win.
  def load_copy_state
    @source_position_id = params[:position_id].presence
    credits = Scheduling::PositionCreditCopier.copyable_credits(@year, position_id: @source_position_id).to_a
    @total_count = credits.size
    @copy_groups = credits.group_by(&:position).sort_by { |position, _credits| position.title }
    @orphan_count = Scheduling::PositionCreditCopier.orphaned_credits(@year, position_id: @source_position_id).count
    @from_labor_day = EventDate.first_monday_of_september(@year)
    @to_labor_day = EventDate.first_monday_of_september(current_year)
    @labor_day_diff = Scheduling::SlotCopier.default_delta_days(@year, current_year)
    @delta = {
      days: delta_param(:delta_days, @labor_day_diff),
      hours: delta_param(:delta_hours, 0),
      minutes: delta_param(:delta_minutes, 0)
    }
    @selected_ids = request.post? ? IdList.parse(params[:credit_ids]) : []
    @position_choices = Position.ordered_by_title.pluck(:title, :id)
  end

  def delta_param(key, default)
    params.key?(key) ? params[key].to_i : default
  end
end
