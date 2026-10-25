# frozen_string_literal: true

class Person::PasswordsController < ApplicationController
  include PersonConcern

  before_action :require_admin

  def edit
    @password_form = PersonPasswordForm.new
  end

  def update
    @password_form = PersonPasswordForm.new(password_form_params)
    if @password_form.valid?
      @person.password = @password_form.password
      @person.save!(validate: false)
      redirect_to person_path(@person), success: "Password updated."
      return
    end

    render :edit, status: :unprocessable_entity
  end

  private

  def password_form_params
    params.expect(person_password_form: [:password, :password_confirmation])
  end

  def require_admin
    return if is_admin?

    redirect_to person_path(@person), error: "You are not authorized to manage passwords."
  end
end
