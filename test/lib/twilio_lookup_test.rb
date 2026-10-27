# frozen_string_literal: true

require "test_helper"

# What Look Up a Number sends Twilio for what was typed. Nothing here asks
# Twilio: number_for only works out the number, or why there is none.
class TwilioLookupTest < ActiveSupport::TestCase
  test "a callsign comes first, even one made only of digits" do
    person(:active_ranger).update_columns(callsign: "4748", callsign_normalized: "4748", sms_number: "+14155550142")

    assert_equal ["+14155550142", nil], TwilioLookup.number_for("4748")
  end

  test "a number Twilio has to judge goes as its digits and plus, never with its spaces" do
    {
      "(415) 555-0142" => "+14155550142",
      "+1 415 555 014" => "+1415555014",
      "+44 20 7946 095" => "+44207946095",
      "415 555 014" => "415555014"
    }.each do |typed, sent|
      assert_equal [sent, nil], TwilioLookup.number_for(typed), typed
    end
  end

  test "a number pasted with odd spaces, dashes or invisible marks is still a number" do
    ["+1 415 555 0142", "(415) 555‑0142", "(415) 555–0142", "415/555-0142",
     "‪(415) 555-0142‬"].each do |typed|
      assert_equal ["+14155550142", nil], TwilioLookup.number_for(typed), typed.inspect
    end
  end

  test "nothing but punctuation asks for a number or a callsign, and Twilio is not asked" do
    ["-", "()", "+", "???", " . "].each do |typed|
      assert_equal [nil, "Enter a phone number or a callsign."], TwilioLookup.number_for(typed), typed
    end
  end

  test "a callsign with nothing left once written loosely is no one's, not two people's" do
    # Two callsigns of letters normalize_word drops, as "Ωμέγα" and "Σίγμα" both are.
    [person(:active_ranger), person(:auditor_ranger)].each { |someone| someone.update_columns(callsign_normalized: "") }

    assert_equal [nil, "No Ranger has the callsign Ωμέγα."], TwilioLookup.number_for("Ωμέγα")
  end
end
