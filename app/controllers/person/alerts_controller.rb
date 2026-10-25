# frozen_string_literal: true

class Person::AlertsController < ApplicationController
  layout "person"

  include PersonConcern
  include Alerts::EditingConcern

  authorize_role [Role::ADMIN]

  private

  def alerts_form_path
    person_alerts_path(@person)
  end

  def alerts_back_path
    person_profile_path(@person)
  end


  def admin_acting?
    current_user.has_role?(Role::ADMIN)
  end

  def admin_intent_allowed?(intent)
    return true if intent == PREFERENCES_INTENT
    return true if intent == SMS_STATE_INTENT && has_role?(Role::TECH_NINJA)

    false
  end
end
