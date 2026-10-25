# frozen_string_literal: true

require "test_helper"

class Me::PasswordControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    # Set a known password for testing
    @person.password = "password"
    @person.save!(validate: false)
    sign_in_as(@person)
  end

  # Edit action tests
  test "should get edit when authenticated" do
    get me_profile_edit_password_path
    assert_response :success
    assert_select "form"
    assert_select "input[name='password_form[old_password]']"
    assert_select "input[name='password_form[password]']"
    assert_select "input[name='password_form[password_confirmation]']"
  end

  test "should redirect to login when not authenticated" do
    sign_out
    get me_profile_edit_password_path
    assert_redirected_to root_path
  end

  # Update action - successful password change
  test "should update password with valid old password and new password" do
    post me_profile_password_path, params: {
      password_form: {
        old_password: "password",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    assert_redirected_to me_profile_path
    assert_match(/password changed/i, flash[:notice])

    # Verify the password was actually changed
    @person.reload
    assert @person.authenticate("newpassword123"), "New password should work"
    assert_not @person.authenticate("password"), "Old password should not work"
  end

  test "should update password with minimum length password" do
    post me_profile_password_path, params: {
      password_form: {
        old_password: "password",
        password: "12345678",
        password_confirmation: "12345678"
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert @person.authenticate("12345678"), "New 8-character password should work"
  end

  # Update action - incorrect old password
  test "should reject incorrect old password" do
    post me_profile_password_path, params: {
      password_form: {
        old_password: "wrongpassword",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    assert_response :unprocessable_entity
    assert_select ".text-error", text: /incorrect/i

    # Verify password was not changed
    @person.reload
    assert @person.authenticate("password"), "Original password should still work"
  end

  # Update action - validation failures
  test "should reject missing old password" do
    post me_profile_password_path, params: {
      password_form: {
        old_password: "",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    assert_response :unprocessable_entity
    assert_select ".text-error", text: /can't be blank/i
  end

  test "should reject missing new password" do
    post me_profile_password_path, params: {
      password_form: {
        old_password: "password",
        password: "",
        password_confirmation: ""
      }
    }

    assert_response :unprocessable_entity
    assert_select ".text-error", text: /can't be blank/i
  end

  test "should reject password shorter than 8 characters" do
    post me_profile_password_path, params: {
      password_form: {
        old_password: "password",
        password: "1234567",
        password_confirmation: "1234567"
      }
    }

    assert_response :unprocessable_entity
    assert_select ".text-error", text: /too short/i

    # Verify password was not changed
    @person.reload
    assert @person.authenticate("password"), "Original password should still work"
  end

  test "should reject password confirmation mismatch" do
    post me_profile_password_path, params: {
      password_form: {
        old_password: "password",
        password: "newpassword123",
        password_confirmation: "differentpassword"
      }
    }

    assert_response :unprocessable_entity
    assert_select ".text-error", text: /don't match/i

    # Verify password was not changed
    @person.reload
    assert @person.authenticate("password"), "Original password should still work"
  end

  test "should reject missing password confirmation" do
    post me_profile_password_path, params: {
      password_form: {
        old_password: "password",
        password: "newpassword123",
        password_confirmation: ""
      }
    }

    assert_response :unprocessable_entity
    assert_select ".text-error", text: /don't match/i
  end

  # Authentication requirement tests
  test "should redirect update to login when not authenticated" do
    sign_out
    post me_profile_password_path, params: {
      password_form: {
        old_password: "password",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    assert_redirected_to root_path
  end

  # Edge case tests
  test "should handle multiple validation errors simultaneously" do
    post me_profile_password_path, params: {
      password_form: {
        old_password: "",
        password: "123",
        password_confirmation: "456"
      }
    }

    assert_response :unprocessable_entity
    # Should have multiple errors displayed
    assert_select ".text-error", minimum: 1
  end

  test "should trim and validate password correctly" do
    # Passwords should not be trimmed - whitespace should be preserved
    post me_profile_password_path, params: {
      password_form: {
        old_password: "password",
        password: "  newpass  ",
        password_confirmation: "  newpass  "
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert @person.authenticate("  newpass  "), "Password with spaces should work"
    assert_not @person.authenticate("newpass"), "Trimmed version should not work"
  end

  test "should handle special characters in password" do
    special_password = "P@ssw0rd!#$%"

    post me_profile_password_path, params: {
      password_form: {
        old_password: "password",
        password: special_password,
        password_confirmation: special_password
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert @person.authenticate(special_password), "Password with special characters should work"
  end

  test "should handle unicode characters in password" do
    unicode_password = "pässwörd123"

    post me_profile_password_path, params: {
      password_form: {
        old_password: "password",
        password: unicode_password,
        password_confirmation: unicode_password
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert @person.authenticate(unicode_password), "Password with unicode characters should work"
  end
end
