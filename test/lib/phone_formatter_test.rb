# frozen_string_literal: true

require "test_helper"

class PhoneFormatterTest < ActiveSupport::TestCase
  # What someone typed, the country of their mailing address, and what is stored.
  READ = [
    ["(775) 555-0199", "US", "+17755550199"],
    ["Text 775-555-0199", "US", "+17755550199"],   # words before the number go
    ["775.555.0199 (cell)", "US", "+17755550199"], # and words after it
    ["775-555-0199cell", "US", "+17755550199"],
    ["090-3987-4641携帯", "JP", "+819039874641"],
    ["775 555-0199 EXT 12", "US", "+17755550199"], # an extension goes, digits and all
    ["775 555 0199x12", "US", "+17755550199"],
    ["775-555-0199p12", "US", "+17755550199"],     # a dialer pause
    ["1-775-555-0199", "US", "+17755550199"],
    ["775=555-0199", "US", "+17755550199"],        # "=" for the "-" beside it
    ["416 555 0123", "US", "+14165550123"],        # Toronto: +1 is shared
    ["787 555 0123", "US", "+17875550123"],        # Puerto Rico, which Phonelib codes "1787"
    ["775 555 0199", "CA", "+17755550199"],
    ["0121 496 0497", "GB", "+441214960497"],
    ["0044 121 496 0497", "US", "+441214960497"],
    ["+44 (0)121 496 0497", "US", "+441214960497"],
    ["+1 775 555 0199", "GB", "+17755550199"],
    ["０９０-３９８７-４６４１", "JP", "+819039874641"], # full-width, from a CJK keyboard
    ["090ー3987ー4641", "JP", "+819039874641"],     # a Japanese keyboard's dash
    # Phonelib given no region reads this as a number in Egypt (+20).
    ["201 555 0142", "United States", "+12015550142"], # not a region Phonelib knows: read as US
    ["201 555 0142", nil, "+12015550142"],
    ["201 555 0142", "", "+12015550142"]
  ].freeze

  # Typed, and the country of the mailing address: none of these is stored.
  REFUSED = [
    ["(775) 555-0199", "GB"],  # also a valid UK mobile: refused rather than guessed
    ["441214960497", "US"],    # bare digits never move to another country
    ["011 44 121 496 0497", "US"], # Phonelib does not count 011 as explicit
    # A mistyped digit: dropped, it would leave a shorter number that is still
    # valid in Berlin.
    ["030 12345l7", "DE"],
    ["030 12345 l7", "DE"],
    ["030 12345\u200Bl7", "DE"], # behind a zero-width space from a paste
    ["030 12345!7", "DE"],
    ["775*555*0199", "US"],    # "*" is a shifted 8
    ["030 1234567o", "DE"],
    ["(775) 555-0199 after 6pm", "US"], # a digit in the note: only the number, please
    ["775-555-0199 or 775-555-0100", "US"],
    ["775 555 01999", "US"],
    ["775-555-JOAN", "US"],
    ["none", "US"],
    ["", "US"],
    [nil, "US"]
  ].freeze

  test "e164 reads a number the way Person stores it" do
    READ.each do |typed, country, stored|
      assert_equal stored, PhoneFormatter.e164(typed, country), "#{typed.inspect} from #{country.inspect}"
    end
  end

  test "e164 refuses what it cannot read for certain" do
    REFUSED.each do |typed, country|
      assert_nil PhoneFormatter.e164(typed, country), "#{typed.inspect} from #{country.inspect}"
    end
  end

  test "format shows a +1 number the way North America writes it and the rest behind their code" do
    assert_equal "(775) 555-0199", PhoneFormatter.format("+17755550199")
    assert_equal "(416) 555-0123", PhoneFormatter.format("+14165550123")
    assert_equal "(787) 555-0123", PhoneFormatter.format("+17875550123")
    assert_equal "+44 121 496 0497", PhoneFormatter.format("+441214960497")
  end

  test "format shows anything not stored in E.164 as it was typed" do
    assert_equal "555-1234", PhoneFormatter.format("555-1234")
    assert_equal "enter later", PhoneFormatter.format("enter later")
    # Readable as a US number, but a legacy value the migration refused to
    # guess at (it reads validly from the person's own country too).
    assert_equal "7755550199", PhoneFormatter.format("7755550199")
    assert_equal "", PhoneFormatter.format(nil)
  end
end
