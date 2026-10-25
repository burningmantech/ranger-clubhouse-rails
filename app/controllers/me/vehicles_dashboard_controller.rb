# frozen_string_literal: true

class Me::VehiclesDashboardController < ApplicationController
  layout "me"

  authorize_status Person::WORKING_STATUSES
  before_action :load_dashboard

  def index
  end

  def mvr_submit
    if @vehicle_dashboard.mvr_approved?
      redirect_to me_vehicles_dashboard_path, info: "Your MVR request is already approved."
      return
    end

    if @vehicle_dashboard.mvr_deadline_passed?
      redirect_to me_vehicles_dashboard_path, error: "The MVR request deadline has passed."
      return
    end

    @instructions = Document.find_id_or_tag(Document::MVR_FORM_INSTRUCTIONS_TAG)&.body
  end

  private

  def load_dashboard
    @vehicle_dashboard = VehicleDashboard.new(current_user, Current.year)

    unless @vehicle_dashboard.any_eligible?
      redirect_to me_root_path, error: "You are not eligible to submit MVR Requests or PVRs."
    end
  end
end
