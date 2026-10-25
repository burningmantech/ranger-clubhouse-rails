# frozen_string_literal: true

# The wording of one message the Clubhouse sends: its subject, its HTML body and,
# where the message has one, its plain text body. Templates are written in
# Liquid, so what a message says can be changed without a code change.
#
# A row with no subject is a piece shared by other templates rather than a
# message of its own.
class MailTemplate < ApplicationRecord
  self.table_name = "mail_template"
  self.audit_model = true

  # The tag and description columns hold 191 characters and the subject 500. Say
  # so here as well, so too much text comes back as a message beside the field
  # instead of an error page that throws away everything else the writer typed.
  TEXT_COLUMN_LIMIT = 191
  SUBJECT_COLUMN_LIMIT = 500

  # A tag names the mailer and the action it belongs to, matching the folders the
  # message templates used to live in: "password_reset_mailer/notify".
  TAG_FORMAT = %r{\A[a-z0-9_\-/]+\z}

  # Templates tagged this way are pieces other templates include, not messages.
  SHARED_TAG_PREFIX = "shared/"

  # Which column holds which part of a message. The renderer and the lookup both
  # read this, so a format is described in one place only.
  BODY_COLUMNS = { html: :body, text: :text_body }.freeze

  # Every part written in Liquid, named the way the edit page names it.
  FIELD_NAMES = {
    subject: "subject",
    body: "HTML message",
    text_body: "plain text message"
  }.freeze

  # What a list needs to draw a row. The bodies are left out on purpose: they are
  # the largest columns by far, and a list would carry every template's full text
  # to show none of it.
  LIST_COLUMNS = %w[
    id tag description subject seeded_digest
    created_at updated_at person_create_id person_update_id
  ].freeze

  belongs_to :person_create, class_name: "Person", optional: true
  belongs_to :person_update, class_name: "Person", optional: true

  validates :tag, presence: true, uniqueness: true,
                  length: { maximum: TEXT_COLUMN_LIMIT },
                  format: { with: TAG_FORMAT,
                            message: "The tag may only hold lowercase letters, numbers, dashes, underscores and slashes." }
  validates :description, presence: true, length: { maximum: TEXT_COLUMN_LIMIT }
  validates :subject, length: { maximum: SUBJECT_COLUMN_LIMIT }
  validates :subject, presence: true, unless: :shared_piece?
  validates :body, presence: true

  validate :liquid_parses

  class << self
    # Every template with its creator and editor. Built for the list, so the rows
    # it returns carry no wording -- ask for a template by id when the text
    # itself is needed.
    def find_all
      order(:tag)
        .includes(:person_create, :person_update)
        .select(LIST_COLUMNS)
    end
  end

  # The Liquid source for one part of the message, or nil when the message has no
  # such part.
  def source_for(format)
    self[BODY_COLUMNS.fetch(format)].presence
  end

  # Whether this is a piece included by other templates rather than a message of
  # its own. Only a message of its own needs a subject.
  def shared_piece?
    tag.to_s.start_with?(SHARED_TAG_PREFIX)
  end

  private

  # A template that does not parse would send nothing at all, so the mistake is
  # reported beside the field that holds it rather than at sending time.
  #
  # The whole sentence is spelled out because the name of the field is dropped
  # before the message is shown, and because whoever reads it is editing wording
  # rather than writing code.
  def liquid_parses
    FIELD_NAMES.each do |field, name|
      source = self[field]
      next if source.blank?

      begin
        Liquid::Template.parse(source)
      rescue Liquid::Error => e
        errors.add(field, "The #{name} could not be understood, so it was not saved: #{e.message}")
      end
    end
  end
end
