# frozen_string_literal: true

require "test_helper"

# rubocop:disable Style/ClassAndModuleChildren

class Person::PermissionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include PersonTestFactory

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @ninja = person(:echelon_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VIEW_PII, "View Personal Info")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    ensure_role(Role::MENTOR, "Mentor")

    grant_role(@admin, Role::ADMIN)
    # Tech ninjas reach person management via their admin role; grant both.
    grant_role(@ninja, Role::ADMIN)
    grant_role(@ninja, Role::TECH_NINJA)
  end

  teardown { Rails.cache.clear }

  test "non-privileged user is redirected away" do
    sign_in_as(person(:active_ranger))
    grant_role(@target, Role::TRAINER) # give viewer a management role so PersonConcern lets them in

    get person_permissions_path(@target)

    assert_redirected_to person_path(@target)
  end

  # Clubhouse 2's PersonPolicy#updateRoles is Admin only. Tech Ninja always comes with
  # Admin, but one granted alone must not reach the editor: PersonPermissionForm guards
  # only the Tech Ninja box, so they could grant Admin -- to themselves, too.
  test "a Tech Ninja without Admin is refused the editor and changes no grant" do
    lone_ninja = create_person("LoneNinja")
    grant_role(lone_ninja, Role::MENTOR) # a page role, so PersonConcern lets them in
    grant_role(lone_ninja, Role::TECH_NINJA)
    sign_in_as(lone_ninja)

    get person_path(@target)
    assert_response :success
    assert_select "a[href='#{person_permissions_path(@target)}']", count: 0

    get person_permissions_path(lone_ninja)
    assert_redirected_to person_path(lone_ninja)

    assert_no_changes -> { PersonRole.find_role_ids_for_person(lone_ninja.id).sort } do
      patch person_permissions_path(lone_ninja),
            params: { person_permission_form: { role_ids: [Role::ADMIN, Role::TECH_NINJA, Role::MENTOR].map(&:to_s) + [""] } }
    end
    assert_redirected_to person_path(lone_ninja)
    assert_equal "You do not have permission to edit permissions.", flash[:error]
  end

  test "admin is offered the editor from the overview" do
    sign_in_as(@admin)

    get person_path(@target)

    assert_select "a[href='#{person_permissions_path(@target)}']", count: 1
  end

  test "admin sees a checkbox per role with current grants checked" do
    grant_role(@target, Role::TRAINER)
    sign_in_as(@admin)

    get person_permissions_path(@target)

    assert_response :success
    assert_select "input[type=checkbox]#role-#{Role::TRAINER}[checked]"
    assert_select "input[type=checkbox]#role-#{Role::ADMIN}:not([checked])"
  end

  test "tech ninja checkbox is disabled for a non tech ninja editor" do
    sign_in_as(@admin)

    get person_permissions_path(@target)

    assert_select "input[type=checkbox]#role-#{Role::TECH_NINJA}[disabled]"
  end

  test "update adds and removes roles to match the submission" do
    grant_role(@target, Role::TRAINER)
    sign_in_as(@admin)

    patch person_permissions_path(@target),
          params: { person_permission_form: { role_ids: [Role::ADMIN.to_s, ""] } }

    assert_redirected_to person_path(@target)
    ids = PersonRole.find_role_ids_for_person(@target.id)
    assert_includes ids, Role::ADMIN
    assert_not_includes ids, Role::TRAINER
  end

  test "clearing all roles removes every grant" do
    grant_role(@target, Role::TRAINER)
    sign_in_as(@admin)

    patch person_permissions_path(@target),
          params: { person_permission_form: { role_ids: [""] } }

    assert_empty PersonRole.find_role_ids_for_person(@target.id)
  end

  test "a scope that is not a list of roles is refused rather than clearing every grant" do
    grant_role(@target, Role::TRAINER)
    sign_in_as(@admin)

    [{}, { person_permission_form: "x" }, { person_permission_form: { role_ids: Role::ADMIN.to_s } }].each do |params|
      patch person_permissions_path(@target), params: params

      assert_response :bad_request, params.inspect
    end
    assert_includes PersonRole.find_role_ids_for_person(@target.id), Role::TRAINER
  end

  # Dropped, the junk would read as "fewer roles" and revoke every grant.
  test "a list holding something that is not a role id is refused rather than revoking" do
    grant_role(@target, Role::TRAINER)
    sign_in_as(@admin)

    patch person_permissions_path(@target), params: { person_permission_form: { role_ids: ["", "abc"] } }

    assert_response :bad_request
    assert_includes PersonRole.find_role_ids_for_person(@target.id), Role::TRAINER
  end

  test "non tech ninja cannot remove an existing tech ninja grant" do
    grant_role(@target, Role::TECH_NINJA)
    grant_role(@target, Role::TRAINER)
    sign_in_as(@admin)

    # The disabled Tech Ninja box never posts; only Trainer is submitted.
    patch person_permissions_path(@target),
          params: { person_permission_form: { role_ids: [Role::TRAINER.to_s, ""] } }

    assert_includes PersonRole.find_role_ids_for_person(@target.id), Role::TECH_NINJA
  end

  test "non tech ninja cannot forge a tech ninja grant" do
    sign_in_as(@admin)

    patch person_permissions_path(@target),
          params: { person_permission_form: { role_ids: [Role::TECH_NINJA.to_s, ""] } }

    assert_not_includes PersonRole.find_role_ids_for_person(@target.id), Role::TECH_NINJA
  end

  test "a save error redirects back to the editor and rolls back" do
    grant_role(@target, Role::TRAINER)
    sign_in_as(@admin)

    # 987654 has no Role row, so add_ids_to_person's create! raises inside the
    # transaction, exercising the form's rescue and the controller's error path.
    patch person_permissions_path(@target),
          params: { person_permission_form: { role_ids: [Role::TRAINER.to_s, "987654", ""] } }

    assert_redirected_to person_permissions_path(@target)
    assert_includes PersonRole.find_role_ids_for_person(@target.id), Role::TRAINER
  end

  test "tech ninja editor can grant the tech ninja role" do
    sign_in_as(@ninja)

    patch person_permissions_path(@target),
          params: { person_permission_form: { role_ids: [Role::TECH_NINJA.to_s, ""] } }

    assert_includes PersonRole.find_role_ids_for_person(@target.id), Role::TECH_NINJA
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id: id)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id: role_id)
    RoleManager.purge_person(person.id.to_s)
  end
end
