# frozen_string_literal: true

class Person::SchedulingController < ApplicationController
  layout "person"

  include PersonConcern
  include QualificationsConcern
  include ScheduleConcern

  before_action :set_back_to, only: [:qualifications]

  private

  def schedule_redirect_path(**options)
    person_scheduling_path(@person, **options)
  end

  def set_back_to
    @back_to_url = person_scheduling_path(@person, year: @year)
    @back_to_label = "#{@year} Schedule & Sign-Ups"
    @signups_url = person_scheduling_sign_ups_path(@person)
  end
end
