# frozen_string_literal: true

class Admin::RbsAlertsController < ApplicationController
  layout "admin"

  authorize_role [Role::ADMIN, Role::TECH_NINJA]

  # admin: false -- reading the list is open to both roles, but only the Tech
  # Team may change the wording. The same gate answers the Edit buttons in the
  # view, so the affordance and the guard cannot disagree.
  authorize_ability :manage_rbs_alerts,
                    only: [:edit, :update],
                    roles: [Role::TECH_NINJA],
                    admin: false,
                    deny_to: :admin_rbs_alerts_path,
                    message: "You are not authorized to change alerts."

  before_action :set_alert, only: [:edit, :update]

  def index
    @alerts = Alert.find_all.to_a
  end

  def edit
  end

  def update
    if @alert.update(alert_params)
      redirect_to admin_rbs_alerts_path, success: "#{@alert.title} updated."
      return
    end

    render :edit, status: :unprocessable_entity
  end

  private

  def set_alert
    @alert = Alert.find(params.expect!(:id))
  end

  def alert_params
    params.expect(alert: [:title, :description, :on_playa])
  end
end
