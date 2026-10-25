# frozen_string_literal: true

class Admin::SettingsController < ApplicationController
  layout "admin"

  authorize_role Role::ADMIN

  before_action :set_tech_ninja
  before_action :set_setting, only: [:edit, :update]

  BOOL_OPTIONS = [
    ["true", true],
    ["false", false]
  ].freeze

  def index
    @form = SettingsSearchForm.new(filter: params[:filter])
    @settings = Setting.find_for_query(filter: @form.filter)
  end

  def edit
    @filter = params[:filter]
  end

  def update
    @filter = params[:filter]
    if @setting.update(params.expect(setting: [:value]))
      cache_delete("*")
      flash[:success] = "Setting updated."
      redirect_to action: :index, params: { filter: @filter }
      return
    end

    render action: :edit, status: :unprocessable_entity
  end

  private

  def set_tech_ninja
    @is_tech_ninja = current_user.has_role?(Role::TECH_NINJA)
    true
  end

  def set_setting
    @setting = Setting.find(params.expect!(:id))
    unless @setting
      redirect_to  action: :index, error: "Setting not found."
      return false
    end

    if @setting.is_credential && !@is_tech_ninja
      redirect_to  action: :index, error: "You are not authorized to access that setting."
      return false
    end
    true
  end
end
