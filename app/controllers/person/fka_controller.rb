# frozen_string_literal: true

class Person::FkaController < ApplicationController
  include PersonConcern

  before_action do |controller|
    unless controller.can_manage_callsign_or_status?
      controller.flash[:error] = "You are not authorized to manage callsigns."
      controller.redirect_to person_path(@person)
    end
  end

  before_action :set_person_fka, only: [:edit, :update, :destroy]

  def new
    @person_fka = @person.person_fka.build
  end

  def create
    @person_fka = @person.person_fka.build(person_fka_params)

    if @person_fka.save
      flash[:notice] = "FKA record created."
      redirect_to edit_person_callsign_path(@person)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @person_fka.update(person_fka_params)
      flash[:notice] = "FKA record updated."
      redirect_to edit_person_callsign_path(@person)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @person_fka.destroy
    flash[:notice] = "FKA record deleted."
    redirect_to edit_person_callsign_path(@person)
  end

  private

  def set_person_fka
    @person_fka = @person.person_fka.find(params[:id])
  end

  def person_fka_params
    params.expect(person_fka: [:fka])
  end
end
