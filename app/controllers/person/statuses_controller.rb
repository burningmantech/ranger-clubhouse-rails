# frozen_string_literal: true

class Person::StatusesController < ApplicationController
  include PersonConcern

  before_action do |controller|
    unless can_manage_callsign_or_status?
      flash[:error] = "You are not authorized to manage the status."
      redirect_to person_path(@person)
    end
  end

  def edit
  end

  def update
    @person.attributes = params.expect(person: [:status])
    if @person.save
      redirect_to person_path(@person), success: "Status updated."
      return
    end

    flash[:error] = "Error updating the status."
    render :edit, status: :unprocessable_entity
  end
end
