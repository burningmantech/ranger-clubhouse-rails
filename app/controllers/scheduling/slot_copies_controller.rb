# frozen_string_literal: true

class Scheduling::SlotCopiesController < ApplicationController
  layout "scheduling"

  authorize_role [Role::ADMIN, Role::EDIT_SLOTS],
                 message: "Admin or Edit Slots role required to manage slots."

  before_action :setup_year
  before_action :load_copy_state

  def new
  end

  def create
    # The "Update Preview" submit re-renders the form with the submitted
    # deltas/selections applied; nothing is copied.
    return render :new, status: :unprocessable_entity if params[:preview]

    result = Scheduling::SlotCopier.copy(year: @year,
                                         ids: @selected_ids,
                                         delta: @delta,
                                         new_position_id: params[:new_position_id].presence,
                                         activate: params[:activate] == "1",
                                         overrides: override_params)

    if result.success?
      redirect_to scheduling_slots_path(year: @year),
                  success: "#{result.slots.size} #{"slot".pluralize(result.slots.size)} copied."
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
    all_slots = Scheduling::SlotCopier.copyable_slots(@year, position_id: @source_position_id).to_a
    @total_count = all_slots.size
    build_filter_options(all_slots)
    @filter = filter_params
    filtered = apply_filters(all_slots)
    @shown_count = filtered.size
    @filtering = @filter.any?
    @copy_groups = filtered.group_by(&:position)
                           .sort_by { |position, _slots| position.title }
    @from_labor_day = EventDate.first_monday_of_september(@year)
    @to_labor_day = EventDate.first_monday_of_september(current_year)
    @labor_day_diff = Scheduling::SlotCopier.default_delta_days(@year, current_year)
    @delta = {
      days: delta_param(:delta_days, @labor_day_diff),
      hours: delta_param(:delta_hours, 0),
      minutes: delta_param(:delta_minutes, 0)
    }
    @selected_ids = request.post? ? IdList.parse(params[:slot_ids]) : []
    @position_choices = Position.ordered_by_title.pluck(:title, :id)
  end

  def delta_param(key, default)
    params.key?(key) ? params[key].to_i : default
  end

  # Filter params live under filter[...] so they never collide with the
  # top-level description/max/url override fields on the copy form.
  def filter_params
    scoped_params(:filter, :description, :date, :time, :datetime).to_h.compact_blank
  end

  # Distinct filter choices drawn from the copyable set so no filter can select
  # an empty result. Times use the stored wall-clock, matching how the page
  # renders each slot's begins.
  def build_filter_options(slots)
    @description_options = slots.map(&:description).compact_blank.uniq.sort_by(&:downcase)
    @date_options = slots.map { |slot| slot.begins.to_date }.uniq.sort
    @time_options = slots.map { |slot| slot.begins.strftime(DateTimeHelper::HOUR_MINS) }.uniq.sort
    @datetime_options = slots.map(&:begins).uniq.sort
  end

  # Narrows the copyable slots by the filter[...] params. Done in Ruby (the set
  # is already loaded to group/render) so time-of-day matching needs no raw SQL.
  def apply_filters(slots)
    filters = @filter
    slots = slots.select { |slot| slot.description == filters[:description] } if filters[:description]
    slots = slots.select { |slot| slot.begins.to_date.iso8601 == filters[:date] } if filters[:date]
    slots = slots.select { |slot| slot.begins.strftime(DateTimeHelper::HOUR_MINS) == filters[:time] } if filters[:time]
    slots = slots.select { |slot| slot.begins.iso8601 == filters[:datetime] } if filters[:datetime]
    slots
  end

  def override_params
    params.permit(:description, :max, :url).to_h.compact_blank
  end
end
