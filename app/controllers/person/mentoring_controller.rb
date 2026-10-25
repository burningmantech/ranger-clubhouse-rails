# frozen_string_literal: true

class Person::MentoringController < ApplicationController
  include MentorHelper
  include PersonConcern
  include MentoringConcern

  layout "person"

  before_action :ensure_can_view,   only: [:index]
  before_action :ensure_can_update, only: [:update]

  helper_method :can_update_mentoring?

  def update
    @form = PersonMentorStatusForm.new(update_params.merge(person: @person))
    if @form.save(actor: current_user)
      redirect_to person_mentoring_path(@person),
                  success: "Mentor status for #{@form.mentor_year} updated."
    else
      index
      render :index, status: :unprocessable_entity
    end
  end

  private

  def update_params
    params.expect(person_mentor_status_form: [:mentor_year, :status])
  end

  def can_update_mentoring?
    has_role? [Role::ADMIN, Role::MENTOR]
  end

  def ensure_can_view
    return if can_update_mentoring? || has_event_management?

    redirect_to person_path(@person), error: "You may not view mentoring records."
  end

  def ensure_can_update
    return if can_update_mentoring?

    redirect_to person_mentoring_path(@person), error: "You may not edit mentor status."
  end
end
