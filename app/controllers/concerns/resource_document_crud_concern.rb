# frozen_string_literal: true

# Resource-document CRUD — the fetch-or-scaffold editor and the actions behind
# it — shared by every page that manages the single document an entity
# publishes: the training interface's Trainer Resources page and Teams &
# Positions › Team Resources. (Laravel: DocumentController's resourceEdit,
# store, update, and resourceDelete.)
#
# An entity points at its document with a resource_tag column rather than a
# foreign key, so this concern owns both halves of that pointer: it derives the
# tag when a document is first written, and clears it when the document goes.
#
# The actions are identical everywhere; only the owning entity, who may edit,
# and the surrounding URLs differ, so each including controller supplies six
# hooks:
#
#   resource_entity          the record that owns the document — must answer
#                            title, resource_tag, build_resource_tag, and
#                            build_resource_title. It must be available
#                            whenever this concern's gate runs, which is when
#                            the concern is included in the callback chain:
#                            set it in a callback that runs earlier (a parent
#                            class's, or one declared above the include), or
#                            memoize a lookup
#   can_manage_resource?     may this viewer create, edit, or delete it — also
#                            what the read page hangs its Edit affordance on
#   resource_show_path       the read page; Save, Cancel, and Delete land here
#   resource_return_label    how the editor's back link names that page
#   resource_form_path       where the form posts — create, update, and delete
#                            all address it
#   resource_document_label  how flashes and errors name the document
#
# The templates live in app/views/common/resource_documents/: each controller
# keeps a one-line edit stub that renders the shared editor (and says who reads
# the document), and each read page renders the shared _document partial under
# its own hero.
#
# The tag is derived, never typed: a first save files the document under the
# entity's derived tag and points the entity at it, while later saves touch the
# body alone. Upstream re-derived the tag on every save, which silently re-filed
# a document whenever its position was renamed — and collided with the unique
# tag index if the new name was taken. Upstream also authorized updates against
# a record whose resource fields were not yet populated, so the trainers this
# feature exists for got a 403 on every save but the first; both are fixed here.
#
# The pointer itself is typed, though, in Team and Position Records, so it is
# only followed when Document.resource_tag says a resource document may live
# there: never a document the code reads by name, a bookmark- page, or a tag no
# document could have.
module ResourceDocumentCrudConcern
  extend ActiveSupport::Concern

  included do
    before_action :authorize_resource_management, only: %i[edit create update destroy]

    helper_method :resource_entity, :can_manage_resource?, :resource_show_path, :resource_return_label,
                  :resource_form_path, :resource_document_label, :resource_document_state
  end

  def edit
    @document = find_resource_document || scaffold_resource_document
  end

  def create
    # A second save from a form opened before the first one landed -- another
    # manager's, or this one's after Back -- edits the document that now exists
    # rather than failing on its tag.
    return update if find_resource_document

    @document = scaffold_resource_document
    return editor_not_loaded unless resource_document_params.key?(:body)
    return reserved_resource_tag unless Document.resource_tag(@document.tag)

    @document.body = submitted_body
    @document.person_create_id = Current.person_id
    @document.person_update_id = Current.person_id

    if @document.save
      sync_resource_tag(@document.tag, "Resource document creation")
      redirect_to resource_show_path, success: "#{resource_document_label.upcase_first} created."
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    # Two first saves at the same moment: both passed the uniqueness check, and
    # the index refused the second.
    @document.errors.add(:base, "Someone saved this document at the same moment. " \
                                "Open it again to see their text before you change it.")
    render :edit, status: :unprocessable_entity
  end

  # Only the body is editable. The tag and the description are left exactly as
  # the first save set them; the entity's pointer is set to the document's own
  # tag, as upstream's update did, which also tidies a pointer that matched it
  # only without regard to case or trailing spaces.
  def update
    @document = find_resource_document
    return resource_document_gone unless @document
    return editor_not_loaded unless resource_document_params.key?(:body)

    @document.body = submitted_body
    @document.person_update_id = Current.person_id if @document.changed?

    if @document.save
      sync_resource_tag(@document.tag, "Resource document update sync")
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

  # What the read page says in place of, or about, the entity's document:
  #   :found     the document is there
  #   :missing   the pointer names a usable tag whose row is gone; a save files
  #              a new document under that tag and repairs the link
  #   :unusable  the pointer names something no resource document may be (see
  #              Document.resource_tag); a save files under the derived tag and
  #              points the entity there instead
  #   :taken     no pointer, but the tag a first save would use already holds a
  #              document the entity does not point at, so a save could only
  #              fail -- an Admin has to relink it
  #   :none      nothing has been written
  def resource_document_state(document)
    return :found if document

    entity = resource_entity
    if entity.resource_tag.present?
      Document.resource_tag(entity.resource_tag) ? :missing : :unusable
    elsif Document.exists?(tag: entity.build_resource_tag)
      :taken
    else
      :none
    end
  end

  # The document the entity currently points at, if the row is still there and
  # the pointer may name a resource document at all. Anything else reads as no
  # document.
  def find_resource_document
    tag = Document.resource_tag(resource_entity.resource_tag)
    tag && Document.find_by(tag:)
  end

  # An unsaved document for the entity. A usable pointer that outlived its row
  # keeps its tag — the form shows what a save will file the document under, and
  # anything already linking to that tag keeps working. Any other pointer gives
  # way to the derived tag.
  def scaffold_resource_document
    entity = resource_entity
    Document.new(tag: Document.resource_tag(entity.resource_tag) || entity.build_resource_tag,
                 description: entity.build_resource_title)
  end

  def resource_document_gone
    redirect_to resource_show_path, error: "The #{resource_document_label} no longer exists."
  end

  # The derived tag itself is one a resource document may not have -- a title
  # starting "Bookmark" derives a bookmark- tag, whose page anyone could read.
  def reserved_resource_tag
    @document.errors.add(:tag, "A #{resource_document_label} cannot be filed under #{@document.tag}. " \
                               "Ask an Admin to give #{resource_entity.title} a different document tag.")
    render :edit, status: :unprocessable_entity
  end

  # Point the entity at its document, or away from it. Saved without validation
  # (as upstream does) so a legacy row that fails a validation added since
  # cannot strand the pointer; the tag written here is always either nil or the
  # document's own, so nothing needs normalizing.
  #
  # Upstream's Team and Position were audited models, so the change was logged
  # as team-update / position-update. Here neither is, so the row is written by
  # hand, as Team Records and Position Records write theirs.
  def sync_resource_tag(tag, reason)
    entity = resource_entity
    was = entity.resource_tag
    return if was == tag

    entity.resource_tag = tag
    entity.audit_reason = reason
    entity.save!(validate: false)
    return if entity.class.audit_model

    ActionLog.record(Current.person, "#{entity.class.table_name}-update", reason,
                     { "resource_tag" => [was, tag], "id" => entity.id })
  end

  # The editor is a form control only once its script has run, and it is this
  # form's only field. A form sent before then carries no document at all, which
  # `params.expect` answers with a 400. Read leniently instead, so that the
  # actions can tell "nothing was sent" from "an empty text was sent".
  def resource_document_params
    scoped_params(:document, :body)
  end

  # What was typed, cleaned on the way in. The people who may write a resource
  # document are not admins. The read pages clean it again on the way out, for
  # documents written before this app existed.
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
