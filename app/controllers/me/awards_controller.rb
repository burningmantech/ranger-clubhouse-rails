# frozen_string_literal: true

class Me::AwardsController < ApplicationController
  layout "me"

  def index
    all_awards = PersonAward.retrieve_for_person(current_user.id)
    @teams = all_awards[:teams]
    @positions = all_awards[:positions]
    @special = all_awards[:special]
  end
end
