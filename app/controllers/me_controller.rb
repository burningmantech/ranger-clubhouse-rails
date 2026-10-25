# frozen_string_literal: true

class MeController < ApplicationController
  layout "me"

  def index
  end


  def event_info
    @title = "Event Info for #{current_user.callsign}"
  end

  def personal_info
  end
end
