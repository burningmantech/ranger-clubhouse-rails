# frozen_string_literal: true

# Checks proposed handles against existing callsigns and reserved handles.
class Vc::HandleCheckerController < ApplicationController
  layout "vc"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to check handles."

  def index
    @checker = HandleChecker.new
    @form = Vc::HandleCheckerForm.from_params(params, default_entity_types: @checker.default_entity_types)
    @results = @form.checked_names.map { |name| [name, @checker.check(name, **@form.check_options)] }
  end
end
