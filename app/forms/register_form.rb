# frozen_string_literal: true

# The details someone gives to open an auditor account for themselves.
#
# The account itself is a Person, which already knows every rule for its own
# columns. This form adds what a Person cannot carry: the password typed twice,
# the reason the account is being opened, and the question that keeps robots
# from filling the page in by the thousand.
#
# Anyone can reach this form, so the account it makes is always an auditor and
# its callsign is always handed out by the Clubhouse. Neither is asked for.
class RegisterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  # The fields that belong to the account itself, in the order they are asked
  # for. Also the list the controller permits.
  PERSON_ATTRIBUTES = %i[
    email first_name mi last_name
    country street1 apt street2 city state zip home_phone alt_phone
  ].freeze

  # Offered as a reason on purpose. Readers who mean to become a Ranger pick it
  # however plainly they are told this account is not that path, so naming it is
  # how the Clubhouse catches them rather than opening an auditor account they
  # did not want. Choosing it opens nothing: it turns the reader toward the
  # Volunteer Form -- on the spot in the browser (register_intent_controller,
  # which reveals the note and holds the submit) and again on the server, checked
  # before the form is ever validated, for anyone without JavaScript.
  RANGER_INTENT = "Ranger"

  # Why the account is being opened. The stored value is the short code; the
  # sentence beside it is both the label on the page and what the note to the
  # Volunteer Coordinators says the person intends to do. "Become a Ranger" is on
  # the list by design -- see RANGER_INTENT for why an answer that turns the
  # reader around still earns a place.
  INTENT_OPTIONS = [
    ["Regional Ranger — not a Black Rock Ranger this year", "Regional"],
    ["Audit training — not becoming a Ranger this year", "Sitin"],
    ["Become a Black Rock Ranger at Burning Man this year", RANGER_INTENT],
    ["Other reason", "Other"]
  ].freeze

  # The sum a reader is asked for before the account is opened. Both halves of
  # the question come from the same two numbers, so the question on the page
  # and the answer checked here cannot drift apart.
  HUMAN_ADDENDS = [33, 2].freeze
  HUMAN_QUESTION = "What is #{HUMAN_ADDENDS.join(" + ")}?".freeze
  HUMAN_ANSWER = HUMAN_ADDENDS.sum

  # What each of the account's own fields is called on this page.
  #
  # The Clubhouse prints a complaint without the name of the field in front of
  # it, which reads well under the field it belongs to and reads as a column of
  # identical complaints in the summary at the top of the form. Naming the field
  # in the sentence fixes the summary without costing the field anything.
  FIELD_NAMES = {
    email: "Email address",
    first_name: "Legal first name",
    mi: "Middle initial",
    last_name: "Legal last name",
    country: "Country",
    street1: "Street line 1",
    apt: "Apt / Unit",
    street2: "Street line 2",
    city: "City",
    state: "State",
    zip: "Postal code",
    home_phone: "Primary phone",
    alt_phone: "Alternative phone"
  }.freeze

  # What the status history says about how the account began.
  STATUS_REASON = "registration"

  PASSWORD_MINIMUM = 8
  PASSWORD_MAXIMUM = 80

  PERSON_ATTRIBUTES.each { |name| attribute name, :string }
  attribute :password, :string
  attribute :password_confirmation, :string
  attribute :intent, :string
  attribute :human_answer, :string

  # Every message here is a whole sentence, because the Clubhouse shows the
  # message on its own rather than after the name of the field.
  validates :intent, inclusion: { in: INTENT_OPTIONS.map(&:last),
                                  message: "Choose why you are creating a Clubhouse account." }
  validate :human_answer_is_right
  validates :password,
            presence: { message: "Choose a password." },
            confirmation: { message: "The two passwords do not match." },
            length: { minimum: PASSWORD_MINIMUM, maximum: PASSWORD_MAXIMUM,
                      message: "The password must be #{PASSWORD_MINIMUM} to #{PASSWORD_MAXIMUM} characters." }
  validates :password_confirmation,
            presence: { message: "Type the password a second time to confirm it." }
  validate :person_is_valid
  validate :callsign_is_available

  # The account as it would be saved. Built once, so the view can ask it which
  # fields it will insist on.
  #
  # Blank values are dropped rather than passed along: a field left out of the
  # request should fall back to what the column stores by default, and the ones
  # that are genuinely required still fail their own checks.
  def person
    @person ||= Person.new(attributes.slice(*PERSON_ATTRIBUTES.map(&:to_s)).compact
                             .merge("status" => Person::AUDITOR))
                      .tap { |person| name_the_account(person) }
  end

  # Saves the account and starts it on its status together, so a failure in
  # either leaves nothing behind.
  #
  # Starting the status is what opens the status history and hands out the
  # positions and roles that come with it, the same as any later status change.
  # Without it an account made here would arrive with none of them.
  def save
    return false unless valid?

    return false unless store_account

    # Told about afterwards, and never allowed to undo it: the account is
    # already open, so a note that cannot be sent is the Clubhouse's problem
    # rather than a reason to turn the reader away from an account they have.
    announce_new_account
    true
  end

  private

  # Writes the account and its first status together, so a failure in either
  # leaves nothing behind. Only this much is guarded: everything after the
  # account is stored has to answer for itself.
  #
  # Starting the status is what opens the status history and hands out the
  # positions and roles that come with it, the same as any later status change.
  # Without it an account made here would arrive with none of them. The account
  # is recorded as its own source, since no one else opened it.
  def store_account
    # Hashing the password is slow, and it needs nothing from the database, so
    # it happens before the transaction opens rather than inside it.
    person.password = password.strip

    Person.transaction do
      person.save!
      PersonStatusManagement.change(person:, old_status: "", reason: STATUS_REASON,
                                    person_source_id: person.id)
    end

    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Two people can pass the checks above at the same moment, and the second
    # one is caught either by the account's own rules or by the database. Which
    # answer they collided on is not worth guessing at, so neither is named.
    errors.add(:base, "The account could not be created. Please try again.")
    false
  rescue ActiveRecord::ValueTooLong
    errors.add(:base, "One of the answers is longer than the Clubhouse can store. Please shorten it.")
    false
  end

  # Auditor callsigns are handed out, never chosen, so one is built as soon as
  # there is a name to build it from. A missing name has its own complaint and
  # is left to make it.
  def name_the_account(person)
    return if person.first_name.blank? || person.last_name.blank?

    # A name made only of marks that fall away when it is simplified leaves
    # nothing to build from. The account is left without a callsign, which the
    # check below turns into something a reader can act on.
    begin
      person.reset_callsign
    rescue
      nil
    end
  end

  # Copies the account's own complaints onto this form, so each one shows beside
  # the field that caused it, naming the field by this form's label.
  def person_is_valid
    return if person.valid?

    person.errors.each do |error|
      name = FIELD_NAMES[error.attribute]
      errors.add(error.attribute, name ? ValidationMessage.naming(error, name) : error.message)
    end
  end

  # No one is asked to fix a callsign they were never asked for. When every
  # spelling of one was already taken, say who can help instead of leaving the
  # account's own complaint about a blank name.
  def callsign_is_available
    person # builds the account, and with it the callsign this answers for

    # The reader is never shown a callsign field, so a complaint about one can
    # only confuse them. Dropped whichever way it arose.
    errors.delete(:callsign)
    return if person.callsign.present?

    # A name that was never given has its own complaint; only a name that was
    # given and still produced no callsign needs explaining.
    return if first_name.blank? || last_name.blank?

    errors.add(:base, "A callsign could not be created from your name. " \
                      "Please contact the Volunteer Coordinators for help.")
  end

  # Digits and nothing else, so "35!" and "thirty five" are turned away as
  # plainly as a wrong sum is.
  def human_answer_is_right
    answer = human_answer.to_s.strip
    return if answer.match?(/\A\d+\z/) && answer.to_i == HUMAN_ANSWER

    errors.add(:human_answer, "That is not the right answer. Please try the sum again.")
  end

  # Lets the Volunteer Coordinators know an account was opened, and why. Sent
  # after the account is safely stored so a note never describes an account
  # that does not exist.
  def announce_new_account
    AccountCreationMailer.notify(status: "success", details: "account created",
                                 person:, intent: intent_description).deliver_later
  rescue => e
    Rails.logger.error("Could not announce new account #{person.callsign}: #{e.class}: #{e.message}")
  end

  # The whole sentence behind the stored code, so the note reads as a sentence.
  def intent_description
    INTENT_OPTIONS.rassoc(intent)&.first || intent
  end
end
