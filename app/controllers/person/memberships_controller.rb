# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren

# Manage a person's team memberships, team manager access, and granted positions.
class Person::MembershipsController < ApplicationController
  include PersonConcern

  before_action :only_team_managers

  def edit
    build_presenter
    @membership_form = PersonMembershipForm.new(
      team_ids: @membership_presenter.selected_team_ids,
      manager_ids: @membership_presenter.selected_manager_ids,
      position_ids: @membership_presenter.selected_position_ids
    )
  end

  def update
    @membership_form = PersonMembershipForm.new(membership_params)

    if @membership_form.save(actor: current_user, person: @person, is_admin: is_admin?)
      redirect_to person_path(@person), success: "Team memberships and positions updated."
      return
    end

    build_presenter
    render :edit, status: :unprocessable_entity
  end

  private

  def build_presenter
    @membership_presenter = PersonMembershipPresenter.new(
      person: @person,
      viewer: current_user,
      selected_team_ids: @membership_form&.team_ids,
      selected_manager_ids: @membership_form&.manager_ids,
      selected_position_ids: @membership_form&.position_ids
    )
  end

  # The form always sends all three lists, each with a hidden blank so that
  # unchecking everything still arrives. expect refuses (400) anything else:
  # read as empty lists, it would clear what the viewer can manage. So is a
  # list holding something that is not an id -- dropped, it would read the
  # same way.
  def membership_params
    form = params.expect(person_membership_form: [team_ids: [], manager_ids: [], position_ids: []])
    return form if form.values.all? { |ids| IdList.clean?(ids) }

    raise ActionController::BadRequest, "a list holds something that is not an id"
  end

  def only_team_managers
    unless is_admin? || is_team_manager?
      redirect_to person_path(@person), error: "You do not manage any Clubhouse Teams."
      false
    end

    true
  end
end
