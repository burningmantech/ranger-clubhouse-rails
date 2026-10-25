# frozen_string_literal: true

class Me::PersonalVehiclesController < ApplicationController
  layout "me"

  before_action :find_vehicle, only: [:edit, :update, :destroy]

  def new
    @vehicle = Vehicle.new(license_state: "CA")
  end

  def create
    @vehicle = Vehicle.new(vehicle_params)
    @vehicle.event_year = current_year
    @vehicle.person_id = current_user.id
    @vehicle.status = Vehicle::PENDING
    @vehicle.type = Vehicle::PERSONAL
    if @vehicle.save
      redirect_to me_vehicles_dashboard_path, success: "Request submitted."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @vehicle.update(vehicle_params)
      redirect_to me_vehicles_dashboard_path, success: "Request updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @vehicle.destroy
    redirect_to me_vehicles_dashboard_path, success: "Vehicle request deleted."
  end

  private

  def vehicle_params
    params.expect(vehicle: [
      :amber_light,
      :driving_sticker,
      :fuel_chit,
      :license_number,
      :license_state,
      :ranger_logo,
      :request_comment,
      :vehicle_class,
      :vehicle_color,
      :vehicle_make,
      :vehicle_model,
      :vehicle_year])
  end

  def find_vehicle
    id = params.expect!(:id)
    @vehicle = Vehicle.find_for_person_year(id, current_user.id, Current.year)
    unless @vehicle
      redirect_to me_vehicles_dashboard_path, error: "Vehicle not found."
      return false
    end

    if @vehicle.status == Vehicle::APPROVED
      redirect_to me_vehicles_dashboard_path, error: "Vehicle request cannot be modified because it has been approved."
      return false
    end

    true
  end
end
