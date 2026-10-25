# frozen_string_literal: true

class Person::AvailableSignUpsController < ApplicationController
  layout "person"

  include PersonConcern
  include AvailableSignUpsConcern

  private

  def schedule_redirect_path(**options)
    person_scheduling_path(@person, **options)
  end

  def sign_ups_redirect_path(**options)
    person_scheduling_sign_ups_path(@person, **options)
  end

  def sign_ups_position_redirect_path(position_id)
    person_scheduling_sign_ups_position_path(@person, position_id)
  end
end
