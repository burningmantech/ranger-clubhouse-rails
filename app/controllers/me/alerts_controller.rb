# frozen_string_literal: true

class Me::AlertsController < ApplicationController
  layout "me"

  # Edited from the profile, which past prospectives keep.
  skip_before_action :confine_past_prospective

  include Alerts::EditingConcern

  before_action :set_person

  private

  def admin_acting?
    false
  end

  def admin_intent_allowed?(intent)
    false
  end

  def set_person
    @person = current_user
  end

  def alerts_form_path
    me_alerts_path
  end

  def alerts_back_path
    me_profile_path
  end
end
