# frozen_string_literal: true

# Manage a person's manually-granted permissions (roles).
class Person::PermissionsController < ApplicationController
  include PersonConcern

  layout "person"

  # Admin only, as Clubhouse 2's PersonPolicy#updateRoles has it. Tech Ninja is always
  # granted together with Admin, so it needs no place here; granting Tech Ninja itself
  # still takes Tech Ninja (PersonPermissionForm#save). PersonConcern#can_edit_permissions?
  # reads this gate for the Overview's edit link.
  authorize_ability :edit_permissions,
                    deny_to: :overview_path,
                    message: "You do not have permission to edit permissions."

  def edit
    @permission_form = PersonPermissionForm.new
    @permission_presenter = build_presenter
  end

  def update
    @permission_form = PersonPermissionForm.new(permission_params)

    if @permission_form.save(actor: current_user, person: @person, is_tech_ninja: has_role?(Role::TECH_NINJA))
      redirect_to person_path(@person), success: "Permissions updated."
    else
      # The form only fails on an unexpected database error (there are no field
      # validations), so redisplaying the submitted selection has no value.
      # Redirect back so the reloaded form reflects the person's real grants.
      redirect_to person_permissions_path(@person),
                  error: @permission_form.errors.full_messages.join(" ").presence || "Unable to update permissions."
    end
  end

  private

  def build_presenter
    PersonPermissionPresenter.new(
      person: @person,
      viewer_is_tech_ninja: has_role?(Role::TECH_NINJA)
    )
  end

  # The form always sends role_ids, with a hidden blank so that unchecking
  # everything still arrives. expect refuses (400) anything else: read as an
  # empty list, it would revoke every direct grant. So is a list holding
  # something that is not a role id -- dropped, it would read the same way.
  def permission_params
    form = params.expect(person_permission_form: [role_ids: []])
    return form if IdList.clean?(form[:role_ids])

    raise ActionController::BadRequest, "role_ids holds something that is not an id"
  end

  def overview_path
    person_path(@person)
  end
end
