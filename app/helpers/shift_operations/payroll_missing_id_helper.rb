# frozen_string_literal: true

module ShiftOperations::PayrollMissingIdHelper
  # Straight to the field that fixes the row, for whoever may edit it. That gate
  # is read off the controller that enforces it rather than restated here, and
  # checked on its own: person_display_link asks first whether the reader may
  # open person pages, which would keep the link from anyone External IDs is
  # later opened to who may not. Everyone else gets the person page when they
  # may open it, or the plain callsign.
  def payroll_missing_id_callsign(person)
    if Current.has_role?(Person::ExternalIdsController.authorized_roles)
      callsign_link(person, person_external_ids_path(person))
    else
      person_display_link(person, person.id)
    end
  end
end
