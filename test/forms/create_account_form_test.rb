# frozen_string_literal: true

require "test_helper"

class CreateAccountFormTest < ActiveSupport::TestCase
  setup do
    Current.reset
    Current.person = person(:active_ranger)
  end

  teardown { Current.reset }

  def build_form(**overrides)
    CreateAccountForm.new(
      { callsign: "Sparkplug", email: "sparkplug@example.com", status: Person::ECHELON,
        first_name: "Spark", mi: "", last_name: "Plug",
        country: "US", street1: "1 Example St", apt: "", street2: "",
        city: "Example City", state: "NV", zip: "99999", home_phone: "775 555 0199",
        password: "a-good-password", password_confirmation: "a-good-password" }.merge(overrides)
    )
  end

  test "the account's own complaints land on the field that caused them" do
    form = build_form(callsign: "")

    assert_not form.valid?
    assert form.errors[:callsign].any?, "a blank callsign is reported against the callsign field"
  end

  test "saving opens the status history and nothing else" do
    form = build_form

    assert_difference "PersonStatus.count", 1 do
      assert_no_difference "EmailHistory.count" do
        assert form.save, form.errors.full_messages.join(", ")
      end
    end
  end

  test "a rejected password writes nothing" do
    form = build_form(password: "short12", password_confirmation: "short12")

    assert_no_difference ["Person.count", "PersonStatus.count"] do
      assert_not form.save
    end
    assert form.errors[:password].any?
  end

  test "a field left out of the request falls back to what the column stores" do
    form = build_form(mi: nil, apt: nil, street2: nil)

    assert form.person.valid?, form.person.errors.full_messages.join(", ")
    assert_equal "", form.person.mi
    assert_equal "", form.person.apt
    assert_equal "", form.person.street2
  end
end
