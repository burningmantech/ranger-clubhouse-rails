# frozen_string_literal: true

require "test_helper"

class RegisterFormTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    Current.reset
    Setting.find_or_initialize_by(name: Setting::ACCOUNT_CREATION_EMAIL)
           .update!(value: "vc@example.com")
  end

  teardown { Current.reset }

  # No one is signed in on the registration page, so no Current.person is set
  # here either -- the account has to be able to open itself.
  def build_form(**overrides)
    RegisterForm.new(
      { email: "sparkplug@example.com",
        first_name: "Spark", mi: "", last_name: "Plug",
        country: "US", street1: "1 Example St", apt: "", street2: "",
        city: "Example City", state: "NV", zip: "99999",
        home_phone: "775 555 0199", alt_phone: "",
        password: "a-good-password", password_confirmation: "a-good-password",
        intent: "Sitin", human_answer: RegisterForm::HUMAN_ANSWER.to_s }.merge(overrides)
    )
  end

  def expected_callsign(last_name: "Plug", first_letter: "S")
    "#{last_name}#{first_letter}#{Current.year % 100}(NR)"
  end

  # ------------------------------------------------------------ the account

  test "an account opens as an auditor with a callsign it was given" do
    form = build_form

    assert form.save, form.errors.full_messages.join(", ")

    person = form.person
    assert person.persisted?
    assert_equal Person::AUDITOR, person.status
    assert_equal expected_callsign, person.callsign
    assert person.authenticate("a-good-password"), "the password chosen on the form signs in"
  end

  test "the account starts its status history" do
    form = build_form

    assert_difference "PersonStatus.count", 1 do
      assert form.save, form.errors.full_messages.join(", ")
    end

    status = PersonStatus.where(person_id: form.person.id).last
    assert_equal Person::AUDITOR, status.new_status
    assert_equal RegisterForm::STATUS_REASON, status.reason
  end

  test "the account arrives with the positions every new account gets" do
    position = Position.create!(title: "Welcome Aboard", active: true, new_user_eligible: true)

    form = build_form
    assert form.save, form.errors.full_messages.join(", ")

    assert PersonPosition.exists?(person_id: form.person.id, position_id: position.id),
           "starting the status hands out the default positions"
  end

  test "the Volunteer Coordinators are told what the account is for" do
    form = build_form(intent: "Regional")

    assert_enqueued_emails 1 do
      assert form.save, form.errors.full_messages.join(", ")
    end
  end

  # ------------------------------------------------------------- the checks

  test "a wrong answer to the sum opens nothing" do
    form = build_form(human_answer: "12")

    assert_no_difference "Person.count" do
      assert_not form.save
    end
    assert form.errors[:human_answer].any?
  end

  test "an answer that is not a number is turned away" do
    form = build_form(human_answer: "thirty five")

    assert_not form.valid?
    assert form.errors[:human_answer].any?
  end

  test "a decorated answer is turned away" do
    form = build_form(human_answer: "35.0")

    assert_not form.valid?
    assert form.errors[:human_answer].any?
  end

  test "a password shorter than the minimum is refused" do
    form = build_form(password: "short12", password_confirmation: "short12")

    assert_no_difference "Person.count" do
      assert_not form.save
    end
    assert form.errors[:password].any?
  end

  test "two different passwords are refused" do
    form = build_form(password_confirmation: "something-else")

    assert_not form.valid?
    assert form.errors[:password_confirmation].any?
  end

  test "a reason has to be picked" do
    form = build_form(intent: "")

    assert_not form.valid?
    assert form.errors[:intent].any?
  end

  test "a made-up reason is refused" do
    form = build_form(intent: "Whatever")

    assert_not form.valid?
    assert form.errors[:intent].any?
  end

  test "the account's own complaints land on the field that caused them" do
    form = build_form(email: "not-an-email", city: "")

    assert_not form.valid?
    assert form.errors[:email].any?
    assert form.errors[:city].any?
  end

  # The address is also the sign-in name, and no reset mail could reach it.
  test "an address no mail could reach is refused, naming the field" do
    form = build_form(email: "name@gmailcom")

    assert_not form.valid?
    assert_equal [I18n.t("errors.messages.email_invalid", attribute: "Email address")], form.errors[:email]
  end

  test "a phone number is asked for" do
    form = build_form(home_phone: "")

    assert_not form.valid?
    assert form.errors[:home_phone].any?
  end

  test "an email address already in use is refused" do
    taken = person(:active_ranger)
    form = build_form(email: taken.email)

    assert_no_difference "Person.count" do
      assert_not form.save
    end
    assert form.errors[:email].any?
  end

  test "nothing is stored when the sum is wrong" do
    form = build_form(human_answer: "1")

    assert_no_difference ["Person.count", "PersonStatus.count"] do
      assert_no_enqueued_emails do
        assert_not form.save
      end
    end
  end


  test "a password typed with stray spaces still signs in" do
    form = build_form(password: "  a-good-password  ",
                      password_confirmation: "  a-good-password  ")

    assert form.save, form.errors.full_messages.join(", ")
    assert form.person.authenticate("a-good-password"),
           "the password is stored the way signing in will read it"
  end

  test "a name that simplifies to nothing is refused, not crashed on" do
    form = build_form(first_name: "\u0301")

    assert_no_difference "Person.count" do
      assert_not form.save
    end
    assert form.errors[:base].any?, "the reader is told a callsign could not be built"
  end

  test "every spelling of a callsign being taken is explained, not left blank" do
    taken = expected_callsign
    10.times do |try|
      last = (try.zero? ? "Plug" : "Plug#{try + 1}")
      Person.create!(callsign: expected_callsign(last_name: last),
                     email: "taken#{try}@example.com",
                     first_name: "Someone", last_name: "Plug", status: Person::AUDITOR,
                     country: "US", street1: "2 Example St", city: "Example City",
                     state: "NV", zip: "99999", home_phone: "775 555 0100",
                     password: "another-password")
    end
    assert Person.exists?(callsign: taken)

    form = build_form
    assert_no_difference "Person.count" do
      assert_not form.save
    end
    assert_match(/callsign could not be created/, form.errors[:base].join(" "))
    assert_empty form.errors[:callsign], "the reader is not asked to fix a field they never saw"
  end

  test "the account records itself as the source of its first status" do
    form = build_form

    assert form.save, form.errors.full_messages.join(", ")
    status = PersonStatus.where(person_id: form.person.id).last
    assert_equal form.person.id, status.person_source_id
  end

  test "the note to the Volunteer Coordinators names the reason in words" do
    form = build_form(intent: "Regional")

    perform_enqueued_jobs do
      assert form.save, form.errors.full_messages.join(", ")
    end

    mail = ActionMailer::Base.deliveries.last
    assert_not_nil mail, "a note is actually delivered, not merely queued"
    assert_equal ["vc@example.com"], mail.to
    assert_match "Regional Ranger", mail.body.to_s
  end

  # Stands in for a queue that cannot be written to.
  class UnreachableQueue
    def enqueue(*)
      raise ActiveRecord::StatementInvalid, "the queue is unreachable"
    end

    def enqueue_at(*)
      raise ActiveRecord::StatementInvalid, "the queue is unreachable"
    end
  end

  test "a note that cannot be sent does not undo the account" do
    form = build_form

    previous = ActiveJob::Base.queue_adapter
    begin
      ActiveJob::Base.queue_adapter = UnreachableQueue.new
      assert form.save, "the account stands even though its note could not be sent"
    ensure
      ActiveJob::Base.queue_adapter = previous
    end

    assert form.person.persisted?
    assert_equal Person::AUDITOR, Person.find(form.person.id).status
  end

  # ------------------------------------------------------------- callsigns

  test "a callsign already taken sends the account to the next spelling" do
    Person.create!(callsign: expected_callsign, email: "taken@example.com",
                   first_name: "Someone", last_name: "Plug", status: Person::AUDITOR,
                   country: "US", street1: "2 Example St", city: "Example City",
                   state: "NV", zip: "99999", home_phone: "775 555 0100",
                   password: "another-password")

    form = build_form
    assert form.save, form.errors.full_messages.join(", ")

    assert_equal expected_callsign(last_name: "Plug2"), form.person.callsign
  end

  test "a missing name is reported once, against the name" do
    form = build_form(last_name: "")

    assert_not form.valid?
    assert form.errors[:last_name].any?
    assert_empty form.errors[:base], "a name that was not given is not also a callsign complaint"
  end
end
