# frozen_string_literal: true

# Looks up a Person by :person_id and turns a miss into a redirect. Each
# including controller defines person_not_found_path -- where a reader goes
# when the id does not resolve -- since there is no default worth guessing.
module PersonLookupConcern
  extend ActiveSupport::Concern

  PERSON_NOT_FOUND = "The person could not be found."

  private

  def set_person
    @person = Person.find_by(id: params[:person_id])
    return if @person

    redirect_to person_not_found_path, error: PERSON_NOT_FOUND
  end
end
