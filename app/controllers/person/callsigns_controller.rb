# frozen_string_literal: true

class Person::CallsignsController < ApplicationController
  include PersonConcern

  before_action do |controller|
    unless can_manage_callsign_or_status?
      flash[:error] = "You are not authorized to manage callsigns."
      redirect_to person_path(@person)
    end
  end

  # Narrower than the page: Clubhouse 2's PersonPolicy#releaseCallsign is Admin or VC,
  # so a Mentor edits the callsign but cannot release it. The same gate answers the
  # Release box on the edit page.
  authorize_ability :release_callsign,
                    roles: [Role::VC],
                    only: :release,
                    deny_to: :release_deny_path,
                    message: "Admin or VC role required to release a callsign."

  helper_method :can_manage_vanity?

  def edit
  end

  def update
    fields = [:callsign]
    fields << :vintage if is_admin?
    fields << :used_vanity_change if can_manage_vanity?
    @person.attributes = params.expect(person: [*fields])
    if @person.save
      redirect_to person_path(@person), success: "Callsign records updated."
      return
    end

    flash[:error] = "Error updating the callsign fields."
    render :edit, status: :unprocessable_entity
  end

  def release
    if @person.vintage
      redirect_to edit_person_callsign_path(@person), error: "The callsign is vintage and may not be released."
    elsif @person.reset_callsign
      @person.callsign_approved = false
      @person.save(validate: false)
      redirect_to edit_person_callsign_path(@person), success: "Callsign released."
    else
      flash[:error] = "The callsign could not be released."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def can_manage_vanity?
    has_role? [Role::ADMIN, Role::VC]
  end

  def release_deny_path
    edit_person_callsign_path(@person)
  end
end
