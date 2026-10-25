# frozen_string_literal: true

# Manage a person's MVR/PVR flags, vehicle agreements, blacklist status,
# and view their vehicle-eligible positions for a given year.
class Person::VehiclesController < ApplicationController
  layout "person"

  include PersonConcern

  before_action :setup_year

  # Admin only: Clubhouse 2 offered these flags and agreements to Admin alone (its
  # event-info page; PersonFilter's RANGER_ADMIN_FIELDS for the blacklist), and its
  # Vehicle Management role only reads vehicles.
  authorize_ability :manage_vehicles,
                    only: %i[update_mvr_flags update_pvr_flags update_agreements update_blacklist],
                    deny_to: :vehicles_deny_path,
                    message: "Admin permission required to update vehicle records."

  require_current_year_for only: %i[update_mvr_flags update_pvr_flags update_agreements],
                           deny_to: :vehicles_deny_path,
                           message: "Vehicle authorizations may only be changed for the current year."

  def index
    load_index_data
  end

  def update_mvr_flags
    @person_event = PersonEvent.first_or_new_for_person_year(@person.id, @year)
    if @person_event.update(mvr_flag_params)
      redirect_index(success: "MVR flags updated.")
    else
      render_index(status: :unprocessable_entity)
    end
  end

  def update_pvr_flags
    @person_event = PersonEvent.first_or_new_for_person_year(@person.id, @year)
    if @person_event.update(pvr_flag_params)
      redirect_index(success: "Personal vehicle flags updated.")
    else
      render_index(status: :unprocessable_entity)
    end
  end

  def update_agreements
    @person_event = PersonEvent.first_or_new_for_person_year(@person.id, @year)
    if @person_event.update(agreement_params)
      redirect_index(success: "Vehicle agreements updated.")
    else
      render_index(status: :unprocessable_entity)
    end
  end

  def update_blacklist
    if @person.update(blacklist_params)
      redirect_index(success: "Vehicle blacklist updated.")
    else
      render_index(status: :unprocessable_entity)
    end
  end

  private

  def load_index_data
    @years = available_years
    @is_current_year = (@year == Current.year)
    @person_event ||= PersonEvent.first_or_new_for_person_year(@person.id, @year)
    @can_edit = @is_current_year && can?(:manage_vehicles)
    @can_admin = can?(:manage_vehicles)

    @mvr_eligible = VehicleEligibility.is_mvr_eligible?(@person.id, @person_event, @year)
    @mvr_positions = Position.vehicle_eligible_for_person("mvr", @person.id)
    @mvr_signups = PersonSlot.retrieve_mvr_signups(@person.id, @year)
    @mvr_teams = PersonTeam.retrieve_mvr_eligible_for_person(@person.id)

    @pvr_eligible = VehicleEligibility.is_pvr_eligible?(@person.id, @person_event, @year)
    @pvr_positions = Position.vehicle_eligible_for_person("pvr", @person.id)
    @pvr_teams = PersonTeam.retrieve_pvr_eligible_for_person(@person.id)
  end

  def mvr_flag_params
    params.expect(person_event: [:org_vehicle_insurance, :mvr_eligible, :ignore_mvr])
  end

  def pvr_flag_params
    params.expect(person_event: [:may_request_stickers, :ignore_pvr])
  end

  def agreement_params
    params.expect(person_event: [:signed_motorpool_agreement, :signed_personal_vehicle_agreement])
  end

  def blacklist_params
    params.expect(person: [:vehicle_blacklisted])
  end

  def vehicles_deny_path
    person_vehicles_path(@person, year: @year)
  end

  def available_years
    years = PersonEvent.where(person_id: @person.id).distinct.pluck(:year).compact
    years_with_current(years)
  end

  def redirect_index(**flash_hash)
    redirect_to person_vehicles_path(@person, year: @year), **flash_hash
  end

  def render_index(status:)
    load_index_data
    render :index, status:
  end
end
