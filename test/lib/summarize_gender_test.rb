# frozen_string_literal: true

require "test_helper"

# The gender codes the Shift Lead Report's roster prints.
class SummarizeGenderTest < ActiveSupport::TestCase
  test "each stated identity maps to its code" do
    {
      Gender::GENDER_CIS_FEMALE => "F",
      Gender::GENDER_CIS_MALE => "M",
      Gender::GENDER_FEMALE => "F",
      Gender::GENDER_MALE => "M",
      Gender::GENDER_FLUID => "GF",
      Gender::GENDER_NON_BINARY => "NB",
      Gender::GENDER_QUEER => "Q",
      Gender::GENDER_TRANS_FEMALE => "TF",
      Gender::GENDER_TRANS_MALE => "TM",
      Gender::GENDER_TWO_SPIRIT => "TS"
    }.each do |identity, code|
      assert_equal code, SummarizeGender.parse(identity, nil), identity
    end
  end

  test "not stated is blank" do
    assert_equal "", SummarizeGender.parse(Gender::GENDER_NONE, nil)
    assert_equal "", SummarizeGender.parse(nil, nil)
  end

  # A schema change no one taught the report about should look wrong rather than
  # pass for "not stated".
  test "an identity the map has never heard of reads as a question mark" do
    assert_equal "?", SummarizeGender.parse("agender", nil)
  end

  test "a custom identity is read for what it says" do
    {
      "Female" => "F",
      "f" => "F",
      "cis female" => "F",
      "she/her" => "F",
      # Carried over from upstream with its misspellings intact.
      "famale" => "F",
      "Male" => "M",
      "m" => "M",
      "dude" => "M",
      "non-binary" => "NB",
      "non binary" => "NB",
      "genderqueer person is queer" => "Q",
      "gender fluid" => "GF"
    }.each do |custom, code|
      assert_equal code, SummarizeGender.parse(Gender::GENDER_CUSTOM, custom), custom
    end
  end

  test "a custom identity saying nothing is blank" do
    assert_equal "", SummarizeGender.parse(Gender::GENDER_CUSTOM, nil)
    assert_equal "", SummarizeGender.parse(Gender::GENDER_CUSTOM, "   ")
    assert_equal "", SummarizeGender.parse(Gender::GENDER_CUSTOM, "yes")
  end

  # Anything the patterns cannot place is shown as the Ranger wrote it -- the
  # report does not guess, and does not drop what it was told.
  test "an unrecognised custom identity is handed back as typed" do
    assert_equal "Bigender", SummarizeGender.parse(Gender::GENDER_CUSTOM, "Bigender")
  end
end
