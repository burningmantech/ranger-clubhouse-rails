# frozen_string_literal: true

# Opening a Clubhouse account by hand, for someone who did not arrive through
# the application process.
#
# The page collects the account details and its first password together, then
# hands off to the person's own page, which is where positions, roles, and
# teams are granted.
class People::CreateAccountController < ApplicationController
  layout "people"

  authorize_role [Role::ADMIN],
                 message: "Admin role required to create accounts."

  def new
    # The form opens on the status and country most new accounts have, so the
    # address fields start somewhere useful.
    @form = CreateAccountForm.new(status: Person::ECHELON, country: "US")
  end

  def create
    @form = CreateAccountForm.new(form_params)

    if @form.save
      redirect_to person_path(@form.person),
                  success: "Account created for #{@form.person.callsign}."
      return
    end

    # A form answered with a plain 200 is thrown away rather than shown, so a
    # rejected save has to say so with its status or nothing appears to happen.
    render :new, status: :unprocessable_entity
  end

  private

  def form_params
    params.expect(create_account_form: [*CreateAccountForm::PERSON_ATTRIBUTES, :password, :password_confirmation])
  end
end
