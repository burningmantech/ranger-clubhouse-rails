# frozen_string_literal: true

class Scheduling::SlotsController < ApplicationController
  include PositionLookupConcern

  layout "scheduling"

  authorize_role [Role::ADMIN, Role::EDIT_SLOTS],
                 message: "Admin or Edit Slots role required to manage slots."

  before_action :setup_year
  before_action :set_position, only: %i[position set_active_all bulk_destroy]
  before_action :set_slot, only: %i[edit update destroy repeat]

  # Attributes carried over when repeating or cloning a slot. Trainer/parent
  # links are deliberately dropped, mirroring the Ember admin behavior.
  CLONE_ATTRS = %w[begins ends description active position_id max url timezone].freeze

  def index
    @slot_counts = Hash.new(0)
    @inactive_counts = Hash.new(0)
    Slot.for_year(@year).group(:position_id, :active).count.each do |(position_id, active), count|
      @slot_counts[position_id] += count
      @inactive_counts[position_id] += count unless active
    end
    @positions = Position.where(id: @slot_counts.keys).select(:id, :title).ordered_by_title
    @total_slots = @slot_counts.values.sum
    @event_date = EventDate.find_for_year(@year)
  end

  def position
    base = Slot.for_year(@year).for_position(@position.id)
    @total_count = base.count
    @inactive_count = base.where(active: false).count
    @day_options = base.pluck(:begins).map(&:to_date).uniq.sort
    @description_options = base.distinct.pluck(:description).compact_blank.sort_by(&:downcase)
    @filtering = params.values_at(:day, :active, :description).any?(&:present?)
    @slots = apply_filters(base)
             .ordered_by_begins
             .includes(:position, trainer_slot: :position,
                       parent_signup_slot: :position, child_signup_slot: :position)
             .load
    PositionCredit.warm_year_cache(@year, [@position.id])
  end

  def new
    @slot = Slot.new(position_id: params[:position_id].presence, timezone: Slot::DEFAULT_TIMEZONE)
    load_form_collections
  end

  def create
    @slot = Slot.new(slot_params)

    if @slot.save
      redirect_to slot_position_path(@slot), success: "Slot created."
    else
      load_form_collections
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_form_collections
  end

  def update
    if params[:save_as_new]
      save_as_new
    elsif @slot.update(slot_params)
      redirect_to slot_position_path(@slot), success: "Slot updated."
    else
      load_form_collections
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    position_id = @slot.position_id
    @slot.destroy!

    redirect_to scheduling_slots_position_path(position_id, year: @year),
                success: "Slot deleted."
  end

  def repeat
    copy = Slot.new(@slot.attributes.slice(*CLONE_ATTRS))

    if params[:add24]
      copy.begins += 24.hours
      copy.ends += 24.hours
    end

    if copy.save
      message = params[:add24] ? "The slot has been repeated with a 24 hour addition." : "The slot has been repeated."
      redirect_to slot_position_path(copy), success: message
    else
      redirect_to scheduling_slots_position_path(@slot.position_id, year: @year),
                  error: "The slot could not be repeated: #{copy.errors.full_messages.join(" ")}"
    end
  end

  def bulk_destroy
    slots = Slot.for_year(@year).for_position(@position.id).where(id: IdList.parse(params[:slot_ids])).to_a

    if slots.empty?
      return redirect_to scheduling_slots_position_path(@position.id, year: @year),
                         error: "Select at least one slot to delete."
    end

    Slot.transaction { slots.each(&:destroy!) }

    redirect_to scheduling_slots_position_path(@position.id, year: @year),
                success: "#{slots.size} #{"slot".pluralize(slots.size)} deleted."
  end

  def set_active_all
    active = params[:active] == "1"
    slot_ids = Slot.for_year(@year).for_position(@position.id).where.not(active:).ids
    count = Slot.where(id: slot_ids).update_all(active:)
    # update_all skips Slot's callbacks, and an active trainer's slot is what counts as teaching.
    Slot.purge_training_role_caches(slot_ids)

    redirect_to scheduling_slots_position_path(@position.id, year: @year),
                success: "#{count} #{"slot".pluralize(count)} #{active ? "activated" : "deactivated"}."
  end

  # Turbo Frame endpoint: re-renders the trainer/parent link fieldsets when the
  # position select changes on the slot form.
  def link_options
    @slot = Slot.new(position_id: params[:position_id].presence,
                     trainer_slot_id: params[:trainer_slot_id].presence,
                     parent_signup_slot_id: params[:parent_signup_slot_id].presence)
    @link_slots = link_slots_for(@slot.position)

    render layout: false
  end

  private

  def position_not_found_path
    scheduling_slots_path(year: @year)
  end

  def set_slot
    @slot = Slot.find(params[:id])
  end

  # Narrows the position listing by the day/active/description filter params.
  # Day values are matched against the position's own slot dates.
  def apply_filters(scope)
    case params[:active]
    when "active" then scope = scope.where(active: true)
    when "inactive" then scope = scope.where(active: false)
    end

    day = @day_options.find { |date| date.iso8601 == params[:day] }
    scope = scope.where(begins: day.all_day) if day

    scope = scope.where(description: params[:description]) if params[:description].present?

    scope
  end

  def slot_position_path(slot)
    scheduling_slots_position_path(slot.position_id, year: slot.begins_year, anchor: "slot-#{slot.id}")
  end

  # The "Create New Slot From This One" submit on the edit form: saves the
  # current form values as a brand new slot, dropping the trainer/parent links.
  def save_as_new
    clone = Slot.new(slot_params.slice(*CLONE_ATTRS))

    if clone.save
      redirect_to scheduling_edit_slot_path(clone, year: clone.begins_year),
                  success: "Slot created from the existing slot."
    else
      @slot.assign_attributes(slot_params)
      @slot.validate
      load_form_collections
      render :edit, status: :unprocessable_entity
    end
  end

  def load_form_collections
    @positions = Position.ordered_by_title.select(:id, :title, :active).to_a
    @link_slots = link_slots_for(@slot.position)
    @cancel_path = if @slot.position_id
                     scheduling_slots_position_path(@slot.position_id, year: @year)
                   else
                     scheduling_slots_path(year: @year)
                   end
  end

  # Slots eligible as trainer/parent links: the slots belonging to the
  # position's parent position for the year being viewed.
  def link_slots_for(position)
    parent_id = position&.parent_position_id
    return [] unless parent_id

    Slot.for_year(@year).for_position(parent_id).ordered_by_begins.includes(:position)
  end

  def slot_params
    params.expect(slot: [:position_id, :description, :begins, :ends, :timezone,
                         :url, :trainer_slot_id, :parent_signup_slot_id, :max, :active])
  end
end
