# frozen_string_literal: true

# The details needed to open a new Clubhouse account.
#
# The account itself is a Person, which already knows every rule for its own
# columns. This form adds the two things a Person cannot carry: the password
# typed twice, and the first row of the account's status history.
class CreateAccountForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  # The fields that belong to the account itself, in the order they are asked
  # for. Also the list the controller permits.
  PERSON_ATTRIBUTES = %i[
    callsign email status first_name mi last_name
    country street1 apt street2 city state zip home_phone
  ].freeze

  # What the status history says about how the account began.
  STATUS_REASON = "Account created"

  PERSON_ATTRIBUTES.each { |name| attribute name, :string }
  attribute :password, :string
  attribute :password_confirmation, :string

  validates :password, presence: true, confirmation: true, length: { minimum: 8, maximum: 80 }
  validates :password_confirmation, presence: true
  validate :person_is_valid

  # The account as it would be saved. Built once, so the view can ask it
  # which fields it will insist on.
  #
  # Blank values are dropped rather than passed along: a field left out of the
  # request should fall back to what the column stores by default, and the
  # ones that are genuinely required still fail their own checks.
  def person
    @person ||= Person.new(attributes.slice(*PERSON_ATTRIBUTES.map(&:to_s)).compact)
  end

  # Saves the account and starts it on its status together, so a failure in
  # either leaves nothing behind.
  #
  # Starting the status is what opens the status history and hands out the
  # positions and roles that come with it, the same as any later status
  # change. Without it an account made here would arrive with none of them.
  def save
    return false unless valid?

    # Hashing the password is slow, and it needs nothing from the database, so
    # it happens before the transaction opens rather than inside it.
    person.password = password

    Person.transaction do
      person.save!
      PersonStatusManagement.change(person:, old_status: "", reason: STATUS_REASON)
    end

    person.persisted?
  rescue ActiveRecord::RecordNotUnique
    # Two people can pass the checks above at the same moment; the database
    # settles it, and the loser is told rather than shown an error page.
    errors.add(:base, "That callsign or email address has just been taken. Please try again.")
    false
  rescue ActiveRecord::ValueTooLong
    errors.add(:base, "One of the values is longer than the Clubhouse can store. Please shorten it.")
    false
  end

  private

  # Copies the account's own complaints onto this form, so each one shows
  # beside the field that caused it.
  def person_is_valid
    errors.merge!(person.errors) unless person.valid?
  end
end
