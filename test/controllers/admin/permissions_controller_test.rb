# frozen_string_literal: true

require "test_helper"

class Admin::PermissionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear

    @admin = person(:auditor_ranger)
    @tech_ninja = person(:echelon_ranger)
    @outsider = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")

    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)

    @permission = Role.create!(id: Role::EDIT_SWAG, title: "Edit Swag Records",
                               new_user_eligible: false)
    @team = teams(:dirt_team)
    TeamRole.create!(team: @team, role_id: @permission.id)

    @training = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                 type: Position::TYPE_TRAINING, active: true)

    # After the fixture rows, so their own audit entries do not stand in for the
    # one a test is looking for.
    ActionLog.delete_all
  end

  teardown do
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- index

  test "admin sees the catalog split into named and composed permissions" do
    Role.create!(id: Role::ART_TRAINER_BASE | @training.id,
                 title: "ART Green Dot Interface", new_user_eligible: false)

    sign_in_as(@admin)

    get admin_permissions_path

    assert_response :success
    assert_select "h1", text: /Permissions/
    assert_select "tbody th", text: /Edit Swag Records/
    # The composed permission is grouped under the position its low bits name,
    # not listed alphabetically beside the rest.
    assert_select "details summary", text: /Green Dot Training/
    assert_select "tbody th", text: /ART Green Dot Interface/
  end

  test "a permission's grants are listed in its detail row" do
    sign_in_as(@admin)

    get admin_permissions_path

    assert_response :success
    assert_select "button[data-toggle-dom-id-value=?]", "permission-detail-#{@permission.id}",
                  text: /1 team/
    assert_select "##{"permission-detail-#{@permission.id}"}", text: /DIRT Team/
  end

  test "a permission nothing grants says so rather than showing an empty cell" do
    Role.create!(id: Role::PAYROLL, title: "Payroll", new_user_eligible: false)

    sign_in_as(@admin)

    get admin_permissions_path

    assert_response :success
    assert_select "td", text: /Direct grant only/
  end

  test "a person with neither role is turned away" do
    sign_in_as(@outsider)

    get admin_permissions_path

    assert_redirected_to me_root_path
  end

  # ----------------------------------------------------------- affordances

  test "tech ninja sees every editing affordance" do
    sign_in_as(@tech_ninja)

    get admin_permissions_path

    assert_response :success
    assert_select "a[href=?]", edit_admin_permission_path(@permission)
    assert_select "a[href=?]", new_art_admin_permissions_path
  end

  test "an admin who is not on the tech team reads the catalog but is offered no writes" do
    sign_in_as(@admin)

    get admin_permissions_path

    assert_response :success
    assert_select "a[href=?]", edit_admin_permission_path(@permission), count: 0
    assert_select "a[href=?]", new_art_admin_permissions_path, count: 0
    assert_select "body", text: /Contact the Tech Team to change a permission/
  end

  # --------------------------------------------------------------- writes

  test "tech ninja renames a permission" do
    sign_in_as(@tech_ninja)

    patch admin_permission_path(@permission),
          params: { role: { title: "Edit Swag", new_user_eligible: "0" } }

    assert_redirected_to admin_permissions_path
    assert_equal "Edit Swag", @permission.reload.title
  end

  test "renaming a permission is recorded in the audit log" do
    sign_in_as(@tech_ninja)

    patch admin_permission_path(@permission),
          params: { role: { title: "Edit Swag", new_user_eligible: "0" } }

    assert ActionLog.where(event: "role-update").exists?
  end

  test "a blank title re-renders the form with the reason" do
    sign_in_as(@tech_ninja)

    patch admin_permission_path(@permission),
          params: { role: { title: "", new_user_eligible: "0" } }

    assert_response :unprocessable_entity
    assert_select "body", text: /Enter a title for the permission/
    assert_equal "Edit Swag Records", @permission.reload.title
  end

  test "an admin who is not on the tech team cannot rename a permission" do
    sign_in_as(@admin)

    patch admin_permission_path(@permission),
          params: { role: { title: "Something else", new_user_eligible: "0" } }

    assert_redirected_to admin_permissions_path
    assert_equal "You are not authorized to change permissions.", flash[:error]
    assert_equal "Edit Swag Records", @permission.reload.title
  end

  test "the delete confirmation names every grant that goes with the permission" do
    PersonRole.create!(person_id: @outsider.id, role_id: @permission.id)

    sign_in_as(@tech_ninja)

    get edit_admin_permission_path(@permission)

    assert_response :success
    assert_select "a[href=?]", admin_permission_path(@permission), text: /Delete Permission/
    assert_select "a[data-turbo-confirm*=?]", "1 team and 1 person"
  end

  test "deleting a permission takes its grants with it" do
    PersonRole.create!(person_id: @outsider.id, role_id: @permission.id)

    sign_in_as(@tech_ninja)

    assert_difference ["Role.count", "TeamRole.count", "PersonRole.count"], -1 do
      delete admin_permission_path(@permission)
    end

    assert_redirected_to admin_permissions_path
    assert_equal "Edit Swag Records deleted.", flash[:success]
  end

  test "a permission that confers admin access cannot be deleted" do
    admin_permission = Role.find(Role::ADMIN)
    TeamRole.create!(team: @team, role_id: admin_permission.id)

    sign_in_as(@tech_ninja)

    assert_no_difference ["Role.count", "TeamRole.count"] do
      delete admin_permission_path(admin_permission)
    end

    assert_redirected_to admin_permissions_path
    assert_match(/cannot be deleted/, flash[:error])
  end

  test "no delete button is offered for a permission that confers admin access" do
    sign_in_as(@tech_ninja)

    get edit_admin_permission_path(Role::TECH_NINJA)

    assert_response :success
    assert_select "a[href=?]", admin_permission_path(Role::TECH_NINJA), count: 0
    assert_select "body", text: /Can this one be deleted\?/
  end

  test "a permission that confers admin access can still be renamed" do
    sign_in_as(@tech_ninja)

    patch admin_permission_path(Role::ADMIN),
          params: { role: { title: "Admin (Full Access)", new_user_eligible: "0" } }

    assert_redirected_to admin_permissions_path
    assert_equal "Admin (Full Access)", Role.find(Role::ADMIN).title
  end

  test "an admin who is not on the tech team cannot delete a permission" do
    sign_in_as(@admin)

    assert_no_difference "Role.count" do
      delete admin_permission_path(@permission)
    end

    assert_redirected_to admin_permissions_path
    assert_equal "You are not authorized to change permissions.", flash[:error]
  end

  # ------------------------------------------------------ ART permissions

  test "the ART picker offers only positions the creation would accept" do
    Position.create!(id: Position::SANDMAN_TRAINING, title: "Sandman Training",
                     type: Position::TYPE_TRAINING, active: false)
    Position.create!(id: Position::MENTOR, title: "Mentor",
                     type: "Frontline", active: true)

    sign_in_as(@tech_ninja)

    get new_art_admin_permissions_path

    assert_response :success
    assert_select "option[value=?]", @training.id.to_s, text: "Green Dot Training"
    assert_select "option[value=?]", Position::SANDMAN_TRAINING.to_s, count: 0
    assert_select "option[value=?]", Position::MENTOR.to_s, count: 0
  end

  test "creating the ART permissions mints the whole set" do
    sign_in_as(@tech_ninja)

    assert_difference "Role.count", Role::ART_ROLE_SUFFIXES.size do
      post art_admin_permissions_path,
           params: { art_permission_form: { position_id: @training.id } }
    end

    assert_redirected_to admin_permissions_path
    assert_equal "Created 4 permissions.", flash[:success]
  end

  test "creating the ART permissions reports the ones that already existed" do
    Role.create!(id: Role::ART_TRAINER_BASE | @training.id,
                 title: "ART Green Dot Interface", new_user_eligible: false)

    sign_in_as(@tech_ninja)

    post art_admin_permissions_path,
         params: { art_permission_form: { position_id: @training.id } }

    assert_redirected_to admin_permissions_path
    assert_equal "Created 3 permissions. 1 permission already existed.", flash[:success]
  end

  test "submitting no position asks for one instead of creating anything" do
    sign_in_as(@tech_ninja)

    assert_no_difference "Role.count" do
      post art_admin_permissions_path, params: { art_permission_form: { position_id: "" } }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /Select the training position to create permissions for/
  end

  test "a position the creation refuses re-renders the form with the reason" do
    inactive = Position.create!(id: Position::SANDMAN_TRAINING, title: "Sandman Training",
                                type: Position::TYPE_TRAINING, active: false)

    sign_in_as(@tech_ninja)

    assert_no_difference "Role.count" do
      post art_admin_permissions_path,
           params: { art_permission_form: { position_id: inactive.id } }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /Position is not active/
  end

  test "an admin who is not on the tech team cannot create ART permissions" do
    sign_in_as(@admin)

    assert_no_difference "Role.count" do
      post art_admin_permissions_path,
           params: { art_permission_form: { position_id: @training.id } }
    end

    assert_redirected_to admin_permissions_path
    assert_equal "You are not authorized to change permissions.", flash[:error]
  end
end
