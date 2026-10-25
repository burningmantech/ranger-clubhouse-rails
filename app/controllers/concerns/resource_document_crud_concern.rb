# frozen_string_literal: true

# Resource-document CRUD — the fetch-or-scaffold editor and the actions behind
# it — shared by every page that manages the single document an entity
# publishes: the training interface's Trainer Resources page today, the team
# resources page when it is ported. (Laravel: DocumentController's resourceEdit,
# store, update, and resourceDelete.)
#
# An entity points at its document with a resource_tag column rather than a
# foreign key, so this concern owns both halves of that pointer: it derives the
# tag when a document is first written, and clears it when the document goes.
#
# The actions are identical everywhere; only the owning entity, who may edit,
# and the surrounding URLs differ, so each including controller supplies five
# hooks:
#
#   resource_entity          the record that owns the document — must answer
#                            resource_tag, build_resource_tag, and
#                            build_resource_title
#   can_manage_resource?     may this viewer create, edit, or delete it — also
#                            what the read page hangs its Edit affordance on
#   resource_show_path       the read page; Save, Cancel, and Delete land here
#   resource_return_label    how the editor's back link names that page
#   resource_form_path       where the form posts — create, update, and delete
#                            all address it
#   resource_document_label  how flashes and errors name the document
#
# The templates live in app/views/common/resource_documents/; each controller
# keeps a one-line stub that renders them. The read page stays host-specific:
# what to say when no document exists is the host's business.
#
# The tag is derived, never typed: a first save files the document under the
# entity's derived tag and points the entity at it, while later saves touch the
# body alone. Upstream re-derived the tag on every save, which silently re-filed
# a document whenever its position was renamed — and collided with the unique
# tag index if the new name was taken. Upstream also authorized updates against
# a record whose resource fields were not yet populated, so the trainers this
# feature exists for got a 403 on every save but the first; both are fixed here.
module ResourceDocumentCrudConcern
  extend ActiveSupport::Concern

  included do
    before_action :authorize_resource_management, only: %i[edit create update destroy]

    helper_method :can_manage_resource?, :resource_show_path, :resource_return_label,
                  :resource_form_path, :resource_document_label
  end

  def edit
    @document = find_resource_document || scaffold_resource_document
  end

  def create
    @document = scaffold_resource_document
    return editor_not_loaded unless resource_document_params.key?(:body)

    @document.body = submitted_body
    @document.person_create_id = Current.person_id
    @document.person_update_id = Current.person_id

    if @document.save
      sync_resource_tag(@document.tag, "Resource document creation")
      redirect_to resource_show_path, success: "#{resource_document_label.upcase_first} created."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Only the body is editable. The tag, the description, and the entity pointer
  # are left exactly as the first save set them.
  def update
    @document = find_resource_document
    return resource_document_gone unless @document
    return editor_not_loaded unless resource_document_params.key?(:body)

    @document.body = submitted_body
    @document.person_update_id = Current.person_id if @document.changed?

    if @document.save
      redirect_to resource_show_path, success: "#{resource_document_label.upcase_first} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @document = find_resource_document
    return resource_document_gone unless @document

    @document.audit_reason = "Resource document deletion"
    @document.destroy!
    sync_resource_tag(nil, "Resource document deletion")
    redirect_to resource_show_path, success: "#{resource_document_label.upcase_first} deleted."
  end

  private

  def authorize_resource_management
    return if can_manage_resource?

    not_authorized_redirect("You are not authorized to manage the #{resource_document_label}.")
  end

  # The document the entity currently points at, if the row is still there. A
  # pointer left behind by a deleted row reads as no document at all.
  def find_resource_document
    tag = resource_entity.resource_tag
    return nil if tag.blank?

    Document.find_by(tag:)
  end

  # An unsaved document for the entity. A pointer that outlived its row keeps
  # its tag — the form shows what a save will file the document under, and
  # anything already linking to that tag keeps working.
  def scaffold_resource_document
    entity = resource_entity
    Document.new(tag: entity.resource_tag.presence || entity.build_resource_tag,
                 description: entity.build_resource_title)
  end

  def resource_document_gone
    redirect_to resource_show_path, error: "The #{resource_document_label} no longer exists."
  end

  # Point the entity at its document, or away from it. Saved without validation
  # (as upstream does) so a legacy row that fails a validation added since
  # cannot strand the pointer; the tag written here is always either nil or the
  # document's own, so nothing needs normalizing.
  def sync_resource_tag(tag, reason)
    entity = resource_entity
    return if entity.resource_tag == tag

    entity.resource_tag = tag
    entity.audit_reason = reason
    entity.save!(validate: false)
  end

  # The editor is a form control only once its script has run, and it is this
  # form's only field. A form sent before then carries no document at all, which
  # `params.expect` answers with a 400. Read leniently instead, so that the
  # actions can tell "nothing was sent" from "an empty text was sent".
  def resource_document_params
    scoped_params(:document, :body)
  end

  # What was typed, cleaned on the way in. The people who may write a resource
  # document are not admins, and both the page that shows it and the admin
  # preview print a document as it is stored.
  def submitted_body
    helpers.rich_text(resource_document_params[:body]).to_s
  end

  # Nothing was saved and nothing is lost: the editor comes back, with what
  # happened said plainly.
  def editor_not_loaded
    flash.now[:error] = "The editor was still loading, so nothing was saved. " \
                        "Wait for its toolbar to appear, then save again."
    render :edit, status: :unprocessable_entity
  end
end
