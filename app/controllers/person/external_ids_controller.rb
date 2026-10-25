# frozen_string_literal: true

class Person::ExternalIdsController < ApplicationController
  layout "person"

  include PersonConcern

  authorize_role [Role::ADMIN]

  def show
  end

  def update
    if @person.update(params.expect(person: [:bpguid, :lms_id, :lms_username, :employee_id]))
      redirect_to person_external_ids_path(@person), success: "External IDs updated."
    else
      flash[:error] = "Error updating the external IDs."
      render :show, status: :unprocessable_entity
    end
  end
end
