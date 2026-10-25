# frozen_string_literal: true

# Administer a person's provisions (meals, showers, event radios).
#
# The actions and the form live in ProvisionCrudConcern, shared with the
# ticketing crew's all-provisions list. What is person-specific is the lookup —
# a provision is only reachable through the person who holds it — and the return
# path, which follows the origin the admin arrived from.
class Person::ProvisionsController < ApplicationController
  layout "person"

  include PersonConcern
  include ProvisionManagementConcern
  include ProvisionCrudConcern

  # Provisions are managed from both the Tickets & Provisions hub (Edit Access
  # Documents) and the BMID page (Edit BMIDs).
  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS, Role::EDIT_BMIDS],
                 message: "Admin, Edit Access Documents, or Edit BMIDs role required to administer provisions."

  private

  def provision_person
    @person
  end

  # Scoped to the person in the URL, so a mismatched id 404s rather than
  # quietly editing someone else's provision.
  def find_provision
    Provision.find_for_person(@person.id, params[:id])
  end

  def provision_form_path(provision)
    if provision.new_record?
      person_provisions_path(@person, origin: provisions_origin)
    else
      person_provision_path(@person, provision, origin: provisions_origin)
    end
  end

  def provision_return_path
    provisions_return_path(@person)
  end

  def provision_return_label
    provisions_origin_label
  end
end
