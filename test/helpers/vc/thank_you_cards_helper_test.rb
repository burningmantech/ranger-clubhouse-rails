# frozen_string_literal: true

require "test_helper"

class Vc::ThankYouCardsHelperTest < ActionView::TestCase
  include Vc::ThankYouCardsHelper

  def build(**attributes)
    Person.new(street1: "", apt: "", street2: "", city: "", state: "", zip: "", **attributes)
  end

  test "puts the apartment on the street line" do
    person = build(street1: "412 Cedar St", apt: "2B", city: "Reno", state: "NV", zip: "89501")

    assert_equal ["412 Cedar St 2B", "Reno, NV 89501"], thank_you_card_address_lines(person)
  end

  # People type the unit designator themselves, so adding one gives "Apt Apt 2B".
  test "does not repeat a unit designator the address already carries" do
    person = build(street1: "412 Cedar St", apt: "Apt 2B", city: "Reno")

    assert_equal ["412 Cedar St Apt 2B", "Reno"], thank_you_card_address_lines(person)
  end

  test "keeps the apartment when there is no street" do
    person = build(apt: "5C", city: "Reno", state: "NV", zip: "89501")

    assert_equal ["5C", "Reno, NV 89501"], thank_you_card_address_lines(person)
  end

  test "keeps a second street line of its own" do
    person = build(street1: "77 Harbor Way", street2: "Unit 300", city: "Oakland", state: "CA", zip: "94607")

    assert_equal ["77 Harbor Way", "Unit 300", "Oakland, CA 94607"], thank_you_card_address_lines(person)
  end

  test "skips the parts that are not on file" do
    person = build(street1: "9 Rue des Lilas", city: "Lyon", zip: "69003")

    assert_equal ["9 Rue des Lilas", "Lyon, 69003"], thank_you_card_address_lines(person)
  end

  test "says nothing when there is no address at all" do
    assert_empty thank_you_card_address_lines(build)
  end

  test "spells out a country code and leaves an unknown one alone" do
    assert_equal "United States", thank_you_card_country("US")
    assert_equal "United States", thank_you_card_country("United States")
    assert_equal "", thank_you_card_country("")
  end

  test "each chip drops only its own status" do
    chips = thank_you_card_filter_chips(2024, [Person::DECEASED, Person::RESIGNED])

    assert_equal ["Including: deceased", "Including: resigned"], chips.map { |chip| chip[:label] }
    assert_match "include_statuses%5B%5D=resigned", chips.first[:url]
    assert_no_match(/deceased/, chips.first[:url])
  end

  test "no chips when nothing was put back" do
    assert_empty thank_you_card_filter_chips(2024, [])
  end

  test "the summary names missing addresses only when there are some" do
    assert_equal "5 people to send cards to", thank_you_card_summary_count(5, 0)
    assert_equal "5 people to send cards to · 2 with no address on file",
                 thank_you_card_summary_count(5, 2)
    assert_equal "No one to send cards to", thank_you_card_summary_count(0, 0)
  end

  test "only the statuses we normally hide get a warning box" do
    hidden = thank_you_card_stat_options(Person::DECEASED)
    normal = thank_you_card_stat_options(Person::ACTIVE)

    assert_equal :warning, hidden[:variant]
    assert_equal :secondary, normal[:variant]
    # The icon has to differ too, or colour is the only signal.
    assert_not_equal hidden[:icon], normal[:icon]
  end
end
