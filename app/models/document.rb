# frozen_string_literal: true

class Document < ApplicationRecord
  self.table_name = "document"
  self.audit_model = true

  # Known document tags
  BEHAVIORAL_STANDARDS_AGREEMENT_TAG = "behavioral-standards-agreement"
  DEPT_NDA_TAG = "dept-nda"
  MOTORPOOL_POLICY_TAG = "motorpool-policy"
  PERSONAL_VEHICLE_AGREEMENT_TAG = "personal-vehicle-agreement"
  RADIO_CHECKOUT_AGREEMENT_TAG = "radio-checkout-agreement"
  SANDMAN_AFFIDAVIT_TAG = "sandman-affidavit"
  MVR_FORM_INSTRUCTIONS_TAG = "mvr-form-instructions"
  DASHBOARD_LINKS_RANGER_TAG = "dashboard-links-ranger"
  DASHBOARD_LINKS_PNV_TAG = "dashboard-links-pnv"
  CONTACTS_RANGER_TAG = "contacts-ranger"
  CONTACTS_PNV_TAG = "contacts-pnv"

  # Documents whose tag starts with this are the link lists the kiosks show, and
  # are the only ones readable without signing in. The page prepends it, so a
  # visitor cannot ask for anything else in this table.
  BOOKMARK_TAG_PREFIX = "bookmark-"

  # What is left of such a tag once the prefix is dropped, and what the address
  # can carry. The bookmark route spells the same rule out again -- routes are
  # drawn before the models are loaded, so it cannot ask here.
  BOOKMARK_SLUG_FORMAT = /\A[A-Za-z0-9_-]+\z/

  # The tag and description columns hold 191 characters. Say so here as well, so
  # too much text comes back as a message beside the field instead of an error
  # page that throws away everything else the writer had typed.
  TEXT_COLUMN_LIMIT = 191

  # What a list of documents needs to draw a row. The body is left out on
  # purpose: it is the largest column by far, and a list would carry every
  # document's full text to show none of it.
  LIST_COLUMNS = %w[
    id tag description refresh_time
    created_at updated_at person_create_id person_update_id
  ].freeze

  # Associations
  belongs_to :person_create, class_name: "Person", optional: true
  belongs_to :person_update, class_name: "Person", optional: true

  # Validations
  validates :tag, presence: true, uniqueness: true, length: { maximum: TEXT_COLUMN_LIMIT }
  validates :description, presence: true, length: { maximum: TEXT_COLUMN_LIMIT }
  validates :body, presence: true
  validates :refresh_time, numericality: { only_integer: true }, allow_nil: true
  validate :tag_contains_no_spaces

  # Normalize refresh_time to nil if empty
  normalizes :refresh_time, with: ->(value) { value.presence }

  # An emptied editor submits empty blocks, which are present? to Ruby and would
  # pass the presence check above.
  normalizes :body, with: BLANK_WHEN_EMPTY_RICH_TEXT

  # Callbacks
  after_save :purge_role_cache
  after_destroy :purge_role_cache

  class << self
    # Find document based on either record id or tag.
    def find_id_or_tag(id_or_tag)
      where(id: id_or_tag).or(where(tag: id_or_tag)).first
    end

    # Find document based on either record id or tag, raises if not found.
    def find_id_or_tag!(id_or_tag)
      where(id: id_or_tag).or(where(tag: id_or_tag)).first!
    end

    # Find all the documents with creator and updater associations. Built for
    # the list, so the rows it returns carry no body -- ask for a document by
    # id when the text itself is needed.
    def find_all
      order(:tag)
        .includes(:person_create, :person_update)
        .select(LIST_COLUMNS)
    end

    # Does a document tag exist?
    def have_tag?(tag)
      exists?(tag: tag)
    end

    # Obtain the document contents (aka body) by tag.
    def contents_by_tag(tag)
      find_by(tag: tag)&.body || ""
    end

    # The tags the Clubhouse looks for by name: the ones named in the code, plus
    # the ones a team or a position points at. Renaming one of these breaks
    # whatever reads it.
    def referenced_tags
      tags = constants.grep(/_TAG\z/).map { |name| const_get(name) }
      tags |= Position.where.not(resource_tag: nil).distinct.pluck(:resource_tag)
      tags |= Team.where.not(resource_tag: nil).distinct.pluck(:resource_tag)
      tags.to_set
    end
  end

  # The kiosk page's address for this document, or nil when it is not a bookmark
  # document. A tag carrying anything the address cannot hold -- a dot, a slash --
  # also answers nil, rather than failing to build a link.
  def bookmark_slug
    return nil unless tag&.start_with?(BOOKMARK_TAG_PREFIX)

    slug = tag.delete_prefix(BOOKMARK_TAG_PREFIX)
    slug.match?(BOOKMARK_SLUG_FORMAT) ? slug : nil
  end

  private

  def tag_contains_no_spaces
    return if tag.blank?

    errors.add(:tag, "The tag may not contain spaces.") if tag.include?(" ")
  end

  # Whether the dept-nda document exists decides whether an unsigned-NDA person
  # keeps their Event Management roles (RoleManager#retrieve_roles), and role
  # sets are cached per person with no expiry. saved_change_to_tag catches a tag
  # renamed away from dept-nda, where +tag+ already holds the new value.
  def purge_role_cache
    return unless tag == DEPT_NDA_TAG || saved_change_to_tag&.include?(DEPT_NDA_TAG)

    RoleManager.purge_all
  end
end
