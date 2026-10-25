# frozen_string_literal: true

class Me::AvailableSignUpsController < ApplicationController
  include AvailableSignUpsConcern

  layout "me"

  before_action :set_person

  authorize_status except: [Person::BONKED, Person::UBERBONKED, Person::PAST_PROSPECTIVE],
                   message: "You are not permitted to view any sign-ups at this time."

  private

  def set_person
    @person = current_user
  end

  def schedule_redirect_path(**options)
    me_schedule_path(**options)
  end

  def sign_ups_redirect_path(**options)
    me_available_sign_up_path(**options)
  end

  def sign_ups_position_redirect_path(position_id)
    me_available_sign_up_position_path(position_id)
  end
end
