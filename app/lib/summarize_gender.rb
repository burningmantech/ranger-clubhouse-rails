# frozen_string_literal: true

# A person's gender identity as the one- or two-letter code the Shift Lead
# Report's roster shows. Upstream Laravel app/Lib/SummarizeGender.php.
#
# The free-text branch exists because "custom" identities are whatever a person
# typed into a text box over more than a decade. The patterns are carried over
# verbatim, misspellings included -- they were written against what people
# actually entered, and tightening them would silently change a real Ranger's
# code on the roster. Anything unrecognised is handed back as typed rather than
# forced into a bucket.
module SummarizeGender
  NONE = ""
  FEMALE = "F"
  MALE = "M"
  NON_BINARY = "NB"
  QUEER = "Q"
  GENDER_FLUID = "GF"
  TRANS_MALE = "TM"
  TRANS_FEMALE = "TF"
  TWO_SPIRIT = "TS"

  # An identity outside this map is a schema change no one taught the report
  # about, so it reads as "?" rather than passing for "not stated".
  UNKNOWN = "?"

  PERSON_GENDER = {
    Gender::GENDER_CIS_FEMALE => FEMALE,
    Gender::GENDER_CIS_MALE => MALE,
    Gender::GENDER_FEMALE => FEMALE,
    Gender::GENDER_FLUID => GENDER_FLUID,
    Gender::GENDER_MALE => MALE,
    Gender::GENDER_NON_BINARY => NON_BINARY,
    Gender::GENDER_QUEER => QUEER,
    Gender::GENDER_TRANS_FEMALE => TRANS_FEMALE,
    Gender::GENDER_TRANS_MALE => TRANS_MALE,
    Gender::GENDER_TWO_SPIRIT => TWO_SPIRIT
  }.freeze

  FEMALE_PATTERN = /\b(female|girl|femme|lady|she|her|woman|famale|femal|fem|cis[\s\-]?female)\b/
  MALE_PATTERN = /\b(male|dude|fella|man|boy)\b/
  NON_BINARY_PATTERN = /\bnon[\s\-]?binary\b/
  QUEER_PATTERN = /\bqueer\b/
  GENDER_FLUID_PATTERN = /\bfluid\b/

  class << self
    def parse(identity, custom = nil)
      return NONE if identity.blank?
      return PERSON_GENDER.fetch(identity, UNKNOWN) unless identity == Gender::GENDER_CUSTOM

      parse_custom(custom)
    end

    private

    def parse_custom(custom)
      check = custom.to_s.strip.downcase
      return NONE if check.blank?

      return FEMALE if check == "f" || check.match?(FEMALE_PATTERN)
      return MALE if check == "m" || check.match?(MALE_PATTERN)
      return NON_BINARY if check.match?(NON_BINARY_PATTERN)
      return QUEER if check.match?(QUEER_PATTERN)
      return GENDER_FLUID if check.match?(GENDER_FLUID_PATTERN)

      # "yes" answers the question that was asked and says nothing.
      return NONE if check == "yes"

      # Undeterminable -- show what they wrote, untouched.
      custom
    end
  end
end
