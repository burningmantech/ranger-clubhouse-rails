# frozen_string_literal: true

class Me::PasswordController < ApplicationController
  layout "me"

  # Part of the profile, which past prospectives keep.
  skip_before_action :confine_past_prospective

  def edit
    @password_form = PasswordForm.new
  end

  def update
    @password_form = PasswordForm.new(params.expect(password_form: [:old_password, :password, :password_confirmation]))
    if @password_form.valid?
      if !current_user.authenticate(@password_form.old_password)
        @password_form.errors.add :old_password, "The current password is incorrect."
        render :edit, status: :unprocessable_entity
      else
        current_user.password = @password_form.password
        current_user.save!
        redirect_to me_profile_path, status: :see_other, notice: "Password changed."
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
