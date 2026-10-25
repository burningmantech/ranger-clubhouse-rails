# frozen_string_literal: true

module MentoringConcern
  extend ActiveSupport::Concern

  included do
    before_action :ensure_person_for_mentoring
  end

  def index
    @mentoring = PersonMentor.retrieve_passing_for_person(@person.id, position_id: Position::ALPHA)
    @mentee_events = PersonMentor.retrieve_mentees_for_person(@person.id, position_id: Position::ALPHA)
    @art_history = ArtMentoring::PersonHistory.new(@person.id)
  end

  private

  def ensure_person_for_mentoring
    @person ||= current_user
  end
end
