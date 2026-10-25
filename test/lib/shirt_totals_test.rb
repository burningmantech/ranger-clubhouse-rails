# frozen_string_literal: true

require "test_helper"

class ShirtTotalsTest < ActiveSupport::TestCase
  include PersonTestFactory

  def shirt(title)
    Swag.create!(title: title, type: Swag::TYPE_DEPT_SHIRT, active: true)
  end

  def person_with(callsign, tshirt: nil, secondary: nil, long_sleeve: nil)
    create_person(callsign).tap do |person|
      person.update!(tshirt_swag: tshirt, tshirt_secondary_swag: secondary,
                     long_sleeve_swag: long_sleeve)
    end
  end

  test "sizes count and sort smallest-first within a style, not alphabetically" do
    large = shirt("Mens Crew L 44\"")
    medium = shirt("Mens Crew M 40\"")
    xl = shirt("Mens Crew XL 48\"")

    people = [
      person_with("ShirtOne", tshirt: xl),
      person_with("ShirtTwo", tshirt: medium),
      person_with("ShirtThree", tshirt: large),
      person_with("ShirtFour", tshirt: medium)
    ]

    sizes = ShirtTotals.for_people(people).first.sizes

    # Alphabetical would put L before M before XL, which reads as nonsense on
    # a sheet whose job is counting out a size run.
    assert_equal ["Mens Crew M 40\"", "Mens Crew L 44\"", "Mens Crew XL 48\""],
                 sizes.map(&:title)
    assert_equal [2, 1, 1], sizes.map(&:count)
  end

  test "a missing size is counted as Unknown and sorts last" do
    people = [
      person_with("ShirtKnown", tshirt: shirt("Mens Crew M 40\"")),
      person_with("ShirtNone")
    ]

    sizes = ShirtTotals.for_people(people).first.sizes

    assert_equal ["Mens Crew M 40\"", ShirtTotals::UNKNOWN], sizes.map(&:title)
    assert_equal [1, 1], sizes.map(&:count)
  end

  test "every shirt kind is reported even when no one has one" do
    kinds = ShirtTotals.for_people([person_with("ShirtBare")])

    assert_equal ["T-Shirts", "T-Shirt Backups", "Long Sleeves"], kinds.map(&:name)
    assert kinds.all? { |kind| kind.sizes.map(&:title) == [ShirtTotals::UNKNOWN] }
  end

  test "an empty group reports no sizes rather than failing" do
    kinds = ShirtTotals.for_people([])

    assert_equal 3, kinds.size
    assert kinds.all? { |kind| kind.sizes.empty? }
  end

  test "title_for is what the rows and the totals both read" do
    person = person_with("ShirtTitled", long_sleeve: shirt("Womens M 42\""))

    assert_equal "Womens M 42\"", ShirtTotals.title_for(person, :long_sleeve_swag)
    assert_equal ShirtTotals::UNKNOWN, ShirtTotals.title_for(person, :tshirt_swag)
  end
end
