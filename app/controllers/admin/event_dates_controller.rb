# frozen_string_literal: true

class Admin::EventDatesController < ApplicationController
  layout "admin"

  # Edit Slots reads this page to see when the pre-event slot window falls, but
  # only the two roles below may change it.
  authorize_role [Role::ADMIN, Role::TECH_NINJA]

  authorize_ability :manage_event_dates,
                    only: [:new, :create, :edit, :update],
                    roles: [Role::TECH_NINJA],
                    deny_to: :admin_event_dates_path,
                    message: "You are not authorized to change event dates."

  # Naming no extra roles leaves this to Admin, who passes every gate implicitly.
  authorize_ability :delete_event_dates,
                    only: [:destroy],
                    deny_to: :admin_event_dates_path,
                    message: "You are not authorized to delete an event date."

  before_action :set_event_date, only: [:edit, :update, :destroy]

  def index
    @event_dates = EventDate.ordered.to_a
  end

  def new
    @event_date = EventDate.new
  end

  def create
    @event_date = EventDate.new(event_date_params)

    if @event_date.save
      redirect_to admin_event_dates_path, success: "Event date created."
      return
    end

    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    if @event_date.update(event_date_params)
      redirect_to admin_event_dates_path, success: "Event date updated."
      return
    end

    render :edit, status: :unprocessable_entity
  end

  def destroy
    @event_date.destroy
    deleted = @stored_year ? "#{@stored_year} event date" : "Event date"
    redirect_to admin_event_dates_path, success: "#{deleted} deleted."
  end

  private

  def set_event_date
    @event_date = EventDate.find(params.expect!(:id))
    # The year as stored, captured before a rejected form re-renders the record
    # with what was typed. The heading and the delete confirmation name the
    # record being acted on, which is never the year in a failed submission.
    @stored_year = @event_date.event_start&.year
  end

  def event_date_params
    params.expect(event_date: [:event_start, :event_end,
                               :pre_event_start, :post_event_end,
                               :pre_event_slot_start, :pre_event_slot_end])
  end
end
