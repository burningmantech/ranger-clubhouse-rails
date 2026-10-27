# frozen_string_literal: true

class Me::OperationalSummaryController < ApplicationController
  layout "me"

  authorize_status except: [Person::AUDITOR, Person::BONKED, Person::UBERBONKED]

  def index
    @person = current_user
    @person_event = PersonEventInfo.find_for_person_year(current_user, current_year)
    @positions = PersonPosition.retrieve_all_for_person(current_user)
    @membership = Membership.retrieve_for_person(current_user)
    # Which of the person's teams have a document to read (Me::TeamDocumentsController),
    # keyed by the pointer as the team stores it. Never a body: the Mentor team's runs to megabytes.
    @team_documents = Document.listed_by_pointer(@membership.teams.map(&:resource_tag))
    @certifications = PersonCertification.retrieve_all_for_person(current_user.id)

    ticketing_period = setting(Setting::TICKETING_PERIOD)
    @provisions_available = ticketing_period == "open" || ticketing_period == "closed"
    if @provisions_available
      @meal_info = MealInfo.new(@person_event)
    end
  end
end
