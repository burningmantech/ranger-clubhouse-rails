# frozen_string_literal: true

require "test_helper"

class Person::PasswordsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @non_admin = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    grant_role(@admin, Role::ADMIN)
    grant_role(@non_admin, Role::TRAINER)

    @target.password = "password"
    @target.save!(validate: false)
  end

  teardown do
    Rails.cache.clear
  end

  test "routes password management on the member password path" do
    assert_routing({ method: "get", path: "/person/#{@target.id}/password" },
                   { controller: "person/passwords", action: "edit", person_id: @target.id.to_s })
    assert_routing({ method: "patch", path: "/person/#{@target.id}/password" },
                   { controller: "person/passwords", action: "update", person_id: @target.id.to_s })
  end

  test "admin can view the password form" do
    sign_in_as(@admin)

    get person_password_path(@target)

    assert_response :success
    assert_select "h1", text: /Change Password/i
    assert_select "form[action='#{person_password_path(@target)}']"
    assert_select "input[name='person_password_form[password]']"
    assert_select "input[name='person_password_form[password_confirmation]']"
    assert_select "input[name='person_password_form[old_password]']", count: 0
  end

  test "non-admin cannot view the password form" do
    sign_in_as(@non_admin)

    get person_password_path(@target)

    assert_redirected_to person_path(@target)
  end

  test "person page shows the change password action for admins" do
    sign_in_as(@admin)

    get person_path(@target)

    assert_response :success
    assert_select "a[href='#{person_password_path(@target)}']", text: /Change Password/
  end

  test "admin can update a person's password" do
    sign_in_as(@admin)
    reset_link = @target.generate_token_for(:password_reset)

    patch person_password_path(@target), params: {
      person_password_form: {
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    assert_redirected_to person_path(@target)
    assert_match(/password updated/i, flash[:success])

    @target.reload
    assert @target.authenticate("newpassword123"), "New password should work"
    assert_not @target.authenticate("password"), "Old password should not work"
    assert_nil Person.find_by_token_for(:password_reset, reset_link), "an outstanding reset link is spent"
  end

  test "invalid password rerenders the form" do
    sign_in_as(@admin)

    patch person_password_path(@target), params: {
      person_password_form: {
        password: "short",
        password_confirmation: "different"
      }
    }

    assert_response :unprocessable_entity
    assert_select ".text-error", minimum: 1

    @target.reload
    assert @target.authenticate("password"), "Original password should still work"
  end

  test "non-admin cannot update a person's password" do
    sign_in_as(@non_admin)

    patch person_password_path(@target), params: {
      person_password_form: {
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    assert_redirected_to person_path(@target)

    @target.reload
    assert @target.authenticate("password"), "Original password should still work"
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id:)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id:)
    RoleManager.purge_person(person.id.to_s)
  end
end
