# frozen_string_literal: true

class Me::ScheduleController < ApplicationController
  include QualificationsConcern
  include ScheduleConcern

  layout "me"

  before_action :set_person
  before_action :set_back_to, only: [:qualifications]

  authorize_status except: [Person::BONKED, Person::UBERBONKED, Person::PAST_PROSPECTIVE],
                   message: "You are not permitted to sign up for trainings or shifts at this time."

  def index
    if @is_current_year
      @permission = Scheduling::Permission.new(@person, @year)
      if @person.is_applicant? && !@permission.training_signups_allowed
        # Without the Online Course an applicant gets a preview instead of the
        # sign-up links: the year's Training sessions by month and description.
        @training_preview_entries, _ = Scheduling::Query.find_for_query(@person.id, @year, position_id: Position::TRAINING)
      end
      @recommend_burn_shift = BurnWeekendShiftRecommendation.recommend?(@person)
    end

    super
  end

  private

  def set_person
    @person = current_user
  end

  def schedule_redirect_path(**options)
    me_schedule_path(**options)
  end

  def set_back_to
    @back_to_url = me_schedule_path(year: @year)
    @back_to_label = "#{@year} Schedule & Sign-Ups"
    @signups_url = me_available_sign_up_path
  end
end
