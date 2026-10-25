# frozen_string_literal: true

require "base64"

# One passkey on an account: a phone, a laptop, a password manager or a
# security key that can sign its owner in without a password.
#
# Only the public half is stored. What proves who someone is never leaves the
# device, so nothing in this table is a secret.
class PersonPasskey < ApplicationRecord
  self.table_name = "person_passkey"
  self.audit_model = true

  # Not a secret, only a hundred characters of noise in every log line.
  self.audit_exclude = %w[public_key].freeze

  # Enough for every device a person owns, and a ceiling on what one account
  # can be made to hold.
  MAX_PER_PERSON = 10
  LIMIT_MESSAGE = "An account can hold #{MAX_PER_PERSON} passkeys. Remove one before adding another."

  NICKNAME_LIMIT = 50

  # The width of the external_id column: the longest id the standard allows.
  EXTERNAL_ID_LIMIT = 1364

  # How many rows the Admin's list of every passkey shows at a time.
  LIST_PAGE_SIZE = 100

  # How far back "used lately" reaches on that list.
  RECENT_USE = 30.days

  belongs_to :person
  # The Admin who enrolled it, when the person did not add it themselves.
  belongs_to :added_by, class_name: "Person", foreign_key: :added_by_person_id, optional: true

  normalizes :nickname, with: ->(value) { value.squish }

  # Whole sentences: the app prints a validation message as written, without
  # putting the field's name in front of it.
  validates :nickname,
            presence: { message: "Give the passkey a nickname." },
            length: { maximum: NICKNAME_LIMIT,
                      message: "The nickname must be #{NICKNAME_LIMIT} characters or fewer." }
  # No two accounts may hold the same passkey, and the unique index is what
  # sees to that: a check here would only race it.
  validates :external_id,
            presence: { message: "The passkey did not say which one it is." },
            length: { maximum: EXTERNAL_ID_LIMIT,
                      message: "That passkey cannot be used here. Try a different device or key." }
  validates :public_key, presence: { message: "The passkey did not include its public key." }
  validate :within_limit, on: :create

  # Put on an account by an Admin rather than by its owner. The column, not
  # the association: see added_by_admin?.
  scope :added_by_an_admin, -> { where.not(added_by_person_id: nil) }

  # What a device files the passkey under. Opaque and no more personal than
  # the number already in every /person/:id address. An account is found by
  # the passkey's own id at sign-in, never by this.
  #
  # @param person [Person]
  # @return [String] the person's id as unpadded base64url
  def self.user_handle(person)
    Base64.urlsafe_encode64(person.id.to_s, padding: false)
  end

  # Whether the account already holds as many passkeys as it may. Asked before
  # a device is told to make one, as well as when one is saved.
  def self.limit_reached?(person)
    where(person_id: person.id).count >= MAX_PER_PERSON
  end

  class << self
    include Pagy::Method

    # One page of every passkey on every account, newest first, for the Admin's
    # list. The id breaks ties so a row cannot sit on two pages, and the page is
    # held to one that exists: a hand-typed number would otherwise ask for rows
    # far past the end and leave an empty table labelled as though it were full.
    #
    # @param added_by_admin [Boolean] only the passkeys an Admin enrolled
    # @param page [Integer]
    # @return [Hash] { passkeys:, meta: { total:, total_pages:, page: } }
    def find_for_list(added_by_admin: false, page: 1)
      scope = includes(:person, :added_by).order(created_at: :desc, id: :desc)
      scope = scope.added_by_an_admin if added_by_admin

      total = scope.count
      last_page = [(total.to_f / LIST_PAGE_SIZE).ceil, 1].max
      pagy_instance, records = pagy(:offset, scope, page: page.to_i.clamp(1, last_page), limit: LIST_PAGE_SIZE,
                                                    count: total, request: { params: {} })

      { passkeys: records, meta: { total: pagy_instance.count, total_pages: pagy_instance.pages, page: pagy_instance.page } }
    end

    # The four numbers above that list.
    def list_stats
      {
        accounts: distinct.count(:person_id),
        passkeys: count,
        used_lately: where(last_used_at: RECENT_USE.ago..).count,
        added_by_admin: added_by_an_admin.count
      }
    end
  end

  # Whether an Admin enrolled this passkey rather than its owner. Asked of the
  # column, not of added_by: the Admin's account may since have been deleted,
  # and a passkey someone else put on an account must never read as self-added.
  def added_by_admin?
    added_by_person_id.present?
  end

  # Record a sign-in. update_columns on purpose: this happens at every
  # sign-in, and is neither a change worth an audit line nor an edit. The real
  # clock rather than Current.time, to agree with created_at beside it -- on
  # the training server Current.time stands still, and a passkey would be
  # last used before it was added.
  #
  # @param sign_count [Integer] the counter the passkey just presented
  def used!(sign_count)
    update_columns(sign_count: sign_count, last_used_at: Time.current)
  end

  private

  def within_limit
    errors.add(:base, LIMIT_MESSAGE) if person && self.class.limit_reached?(person)
  end
end
