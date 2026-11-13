# frozen_string_literal: true

module MentoringConcern
  extend ActiveSupport::Concern

  included do
    before_action :ensure_person_for_mentoring
  end

  def index
    @mentoring = PersonMentor.retrieve_mentor_years_for_person(@person.id, position_id: Position::ALPHA,
                                                                statuses: mentor_year_statuses)
    @mentee_events = PersonMentor.retrieve_mentees_for_person(@person.id, position_id: Position::ALPHA)
    @art_history = ArtMentoring::PersonHistory.new(@person.id)
  end

  private

  # Which Alpha years the page lists, by verdict. A person sees only a year
  # they passed; Person::MentoringController widens it to the bonks.
  def mentor_year_statuses = [PersonMentor::STATUS_PASS]

  def ensure_person_for_mentoring
    @person ||= current_user
  end
end
