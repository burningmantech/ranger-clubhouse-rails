# frozen_string_literal: true

# Training > Trainer Resources (Ember training/:position_id/resources): the one
# document a training position publishes for the people who teach it.
#
# Reading it takes nothing beyond the interface itself — upstream's
# DocumentPolicy admits every signed-in viewer — so the base controller's view
# gate is the only guard on #show. Writing it takes the position's own resource
# management role, which is a different question from running its sessions;
# ResourceDocumentCrudConcern owns those actions.
class Training::ResourcesController < Training::BaseController
  include ResourceDocumentCrudConcern

  def show
    @document = find_resource_document
  end

  private

  # --- ResourceDocumentCrudConcern hooks ---

  def resource_entity = @training

  def resource_show_path = training_resources_path(training_slug)

  def resource_return_label = "Trainer Resources"

  def resource_form_path = training_resources_path(training_slug)

  def resource_document_label = "trainer resource document"

  # Laravel's DocumentController#retrieveResourceEntity. The composed role is
  # granted per position — an ART's trainers manage their own document and
  # no one else's — and admins pass everywhere. Note this is neither the view
  # gate (Mentors and VCs read In-Person Training but write nothing) nor the
  # session gate (running sessions and publishing the document are separately
  # granted).
  #
  # The team rule is upstream's and applies to admins too: every ART belongs to
  # a team, and one that does not is a half-configured position whose document
  # no one should be filing yet. In-Person Training is exempt because it has no
  # team by design.
  def can_manage_resource?
    return false if Training.art?(@training) && @training.team_id.blank?

    has_role?([Role::ADMIN, Role::TRAINER_RESOURCE_MANAGEMENT_BASE | @training.id])
  end
end
