# frozen_string_literal: true

class Me::WorkHistoryController < ApplicationController
  include TimesheetDashboardConcern

  layout "me"

  before_action :set_person
  before_action :setup_year

  include WorkHistoryConcern

  def index
  end

  private

  def set_person
    @person = current_user
  end
end
