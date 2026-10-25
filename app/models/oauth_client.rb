# frozen_string_literal: true

# A website that signs people in with their Clubhouse account. The website
# presents its client id and secret when it asks the Clubhouse to sign
# someone in.
class OauthClient < ApplicationRecord
  self.table_name = "oauth_client"
  self.audit_model = true

  # The log records that a client changed. The key itself is never copied
  # into it -- anyone who could read the log could otherwise use the key.
  self.audit_exclude = %w[secret].freeze

  # How many characters a generated secret has.
  SECRET_LENGTH = 32

  # The three text columns hold 255 characters. Say so here as well, so too
  # much text comes back as a message beside the field instead of an error
  # page that throws away everything else that was typed.
  TEXT_COLUMN_LIMIT = 255

  # Space around a pasted value is invisible on the page but counts when the
  # website presents it, so it is taken off before anything is stored. squish
  # rather than strip: copying a value out of a page brings the wide spaces
  # that strip leaves behind, and those read as ordinary spaces to no one.
  normalizes :client_id, :description, :secret, :redirect_uri, with: ->(value) { value.squish }

  # Associations
  has_many :oauth_codes, dependent: :delete_all

  # Validations
  # Two ids that differ only in capitals are already the same id to the
  # database, which is what stops one website being recorded twice under names
  # that look different. Saying so again here would change nothing and would
  # cost a lookup the database can already answer from its index.
  validates :client_id, presence: true, uniqueness: true,
                        length: { maximum: TEXT_COLUMN_LIMIT }
  validates :description, presence: true, length: { maximum: TEXT_COLUMN_LIMIT }
  validates :secret, presence: true, length: { maximum: TEXT_COLUMN_LIMIT }

  # Where the website is sent back to with a sign-in code: a full web address,
  # compared as written. Nothing after a # -- the browser keeps that part to
  # itself, so a code could never follow it.
  # REDIRECT_URI_FORMAT = %r{\Ahttps?://[^\s#]+\z}
  #validates :redirect_uri, presence: true, length: { maximum: TEXT_COLUMN_LIMIT },
  #                         format: { with: REDIRECT_URI_FORMAT, allow_blank: true }

  # Callbacks
  # A brand new client always gets a secret the Clubhouse made, and anything
  # sent along with it is dropped -- there is nothing yet for a chosen value
  # to match. An existing client is different on purpose: its secret can be
  # set by hand, so a website already using one can be recorded as it stands.
  before_validation :generate_secret, on: :create

  # Scopes
  scope :ordered, -> { order(:client_id) }

  #
  # Give the client a new random secret. The website stops signing people in
  # until its own settings carry the new one.
  #
  # @return [String] the new secret
  #
  def generate_secret
    self.secret = SecureRandom.alphanumeric(SECRET_LENGTH)
  end

  #
  # Whether a code may be sent to an address: one is recorded, and this is
  # it, character for character. Asked when a code is handed out and again
  # when it is redeemed.
  #
  # @param uri [Object] what the website sent, which need not be text
  # @return [Boolean]
  #
  def accepts_redirect_uri?(uri)
    redirect_uri.present? ?  uri == redirect_uri : true
  end
end
