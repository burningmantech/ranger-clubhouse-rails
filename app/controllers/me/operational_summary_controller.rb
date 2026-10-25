# frozen_string_literal: true

class Me::OperationalSummaryController < ApplicationController
  layout "me"

  authorize_status except: [Person::AUDITOR, Person::BONKED, Person::UBERBONKED]

  def index
    @person = current_user
    @person_event = PersonEventInfo.find_for_person_year(current_user, current_year)
    @positions = PersonPosition.retrieve_all_for_person(current_user)
    @membership = Membership.retrieve_for_person(current_user)
    @certifications = PersonCertification.retrieve_all_for_person(current_user.id)

    ticketing_period = setting(Setting::TICKETING_PERIOD)
    @provisions_available = ticketing_period == "open" || ticketing_period == "closed"
    if @provisions_available
      @meal_info = MealInfo.new(@person_event)
    end
  end
end
