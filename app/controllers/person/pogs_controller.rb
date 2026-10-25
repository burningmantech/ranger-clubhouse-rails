# frozen_string_literal: true

# Manage a person's meal and shower pogs (issued/redeemed/cancelled tracking).
class Person::PogsController < ApplicationController
  layout "person"

  include PersonConcern

  before_action :setup_year
  before_action :set_person_pog, only: %i[edit update destroy]

  # Clubhouse 2's PersonPogPolicy: Admin or Event Management (Event Management On Playa
  # counts while RoleManager confers it). HQ issues pogs at end of shift through
  # Hq::ShiftManageController, which this gate does not touch.
  authorize_ability :manage_pogs,
                    roles: [Role::EVENT_MANAGEMENT],
                    except: [:index],
                    deny_to: :pogs_deny_path,
                    message: "Admin or Event Management role required to modify pog records."

  def index
    @person_pogs = PersonPog.find_for_query(person_id: @person.id, year: @year).to_a
    @years = years_with_current(PersonPog.years_for_person(@person.id))
  end

  def new
    @person_pog = PersonPog.new(person_id: @person.id, pog: PersonPog::POG_MEAL)
  end

  def create
    @person_pog = PersonPog.new(person_pog_params.merge(person_id: @person.id, issued_by_id: Current.person.id))

    if @person_pog.save
      redirect_to person_pogs_path(@person, year: @year), success: "Pog saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @person_pog.update(person_pog_params)
      redirect_to person_pogs_path(@person, year: @year), success: "Pog saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @person_pog.destroy
    redirect_to person_pogs_path(@person, year: @year), success: "Pog deleted."
  end

  private

  def set_person_pog
    @person_pog = PersonPog.where(person_id: @person.id).find(params[:id])
  end

  # timesheet_id lets a pog reference the shift entry it was earned on (the HQ
  # end-shift flow passes the just-ended entry's id); PersonPog validates the
  # entry exists and belongs to the person.
  def person_pog_params
    params.expect(person_pog: [:pog, :status, :notes, :timesheet_id])
  end

  def pogs_deny_path
    person_pogs_path(@person, year: @year)
  end
end
