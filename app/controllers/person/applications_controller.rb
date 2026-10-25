# frozen_string_literal: true

# Read-only view of a person's prospective applications. All application
# administration lives on the VC applications pages.
class Person::ApplicationsController < ApplicationController
  layout "person"

  include PersonConcern

  # Narrows the broad person-page gate applied by PersonConcern.
  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to view applications."

  def index
    @applications = ProspectiveApplication.find_for_query(person_id: @person.id).to_a
    # Applications were not recorded before 2015, so an older account may
    # have no application on file.
    @created_prior_to_2015 = @person.created_at.nil? || @person.created_at.year < 2015
  end
end
