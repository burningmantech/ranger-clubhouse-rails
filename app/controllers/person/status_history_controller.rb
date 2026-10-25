# frozen_string_literal: true

# Read-only log of a person's status changes.
class Person::StatusHistoryController < ApplicationController
  layout "person"

  include PersonConcern

  # Narrows the broad person-page gate applied by PersonConcern.
  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to view status history."

  def index
    @history = PersonStatus.retrieve_all_for_id(@person.id).to_a
  end
end
