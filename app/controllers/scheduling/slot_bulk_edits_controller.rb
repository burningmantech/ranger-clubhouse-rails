# frozen_string_literal: true

class Scheduling::SlotBulkEditsController < ApplicationController
  include PositionLookupConcern

  layout "scheduling"

  authorize_role [Role::ADMIN, Role::EDIT_SLOTS],
                 message: "Admin or Edit Slots role required to manage slots."

  before_action :setup_year
  before_action :set_position
  before_action :load_slots

  def new
  end

  def create
    columns = column_params
    slots = @slots.select { |slot| @selected_ids.include?(slot.id) }

    if slots.empty?
      flash.now[:error] = "Select at least one slot to update."
      return render :new, status: :unprocessable_entity
    end

    if columns.empty?
      flash.now[:error] = "Fill in at least one field to apply."
      return render :new, status: :unprocessable_entity
    end

    begin
      Slot.transaction { slots.each { |slot| slot.update!(columns) } }
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:error] =
        "Could not update slot ##{e.record.id}: #{e.record.errors.full_messages.join(" ")} No slots were changed."
      return render :new, status: :unprocessable_entity
    end

    redirect_to scheduling_slots_position_path(columns["position_id"] || @position.id, year: @year),
                success: "#{slots.size} #{"slot".pluralize(slots.size)} updated."
  end

  private

  # This page has no list of its own -- it edits the slots admin's shifts, so a
  # reader who cannot be shown a position belongs back there.
  def position_not_found_path
    scheduling_slots_path(year: @year)
  end

  def load_slots
    all_slots = Slot.for_year(@year)
                    .for_position(@position.id)
                    .ordered_by_begins
                    .to_a
    @total_count = all_slots.size
    build_filter_options(all_slots)
    @filter = filter_params
    @filtering = @filter.any?
    @slots = apply_filters(all_slots)
    @position_choices = Position.ordered_by_title.pluck(:title, :id)
    # Every shown slot is checked on first render; a re-render keeps the submitted selection.
    @selected_ids = request.post? ? IdList.parse(params[:slot_ids]) : nil
  end

  # Filter params live under filter[...] so they never collide with the
  # top-level description/max/url fields applied to the selected slots.
  def filter_params
    scoped_params(:filter, :active, :description, :date, :time, :datetime).to_h.compact_blank
  end

  # Distinct filter choices drawn from the position's whole set so no filter can
  # select an empty result. Times use the stored wall-clock, matching how the
  # page renders each slot's begins.
  def build_filter_options(slots)
    @description_options = slots.map(&:description).compact_blank.uniq.sort_by(&:downcase)
    @date_options = slots.map { |slot| slot.begins.to_date }.uniq.sort
    @time_options = slots.map { |slot| slot.begins.strftime(DateTimeHelper::HOUR_MINS) }.uniq.sort
    @datetime_options = slots.map(&:begins).uniq.sort
  end

  # Narrows the slots by the filter[...] params. Done in Ruby (the set is
  # already loaded to render) so time-of-day matching needs no raw SQL.
  def apply_filters(slots)
    filters = @filter
    slots = slots.select { |slot| slot.active == (filters[:active] == "active") } if filters[:active]
    slots = slots.select { |slot| slot.description == filters[:description] } if filters[:description]
    slots = slots.select { |slot| slot.begins.to_date.iso8601 == filters[:date] } if filters[:date]
    slots = slots.select { |slot| slot.begins.strftime(DateTimeHelper::HOUR_MINS) == filters[:time] } if filters[:time]
    slots = slots.select { |slot| slot.begins.iso8601 == filters[:datetime] } if filters[:datetime]
    slots
  end

  # The fields to apply to every selected slot; blank fields are skipped.
  def column_params
    columns = params.permit(:description, :max, :url).to_h.compact_blank
    columns["position_id"] = params[:new_position_id] if params[:new_position_id].present?
    columns
  end
end
