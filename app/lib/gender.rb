# frozen_string_literal: true

module Gender
  extend OptionsLabels

  # Gender identity constants
  GENDER_CIS_FEMALE = "cis-female"
  GENDER_CIS_MALE = "cis-male"
  GENDER_CUSTOM = "custom"
  GENDER_FEMALE = "female"
  GENDER_FLUID = "fluid"
  GENDER_MALE = "male"
  GENDER_NONE = ""
  GENDER_NON_BINARY = "non-binary"
  GENDER_QUEER = "queer"
  GENDER_TRANS_FEMALE = "trans-female"
  GENDER_TRANS_MALE = "trans-male"
  GENDER_TWO_SPIRIT = "two-spirit"

  GENDER_TYPES = [
    GENDER_CIS_FEMALE,
    GENDER_CIS_MALE,
    GENDER_CUSTOM,
    GENDER_FEMALE,
    GENDER_FLUID,
    GENDER_MALE,
    GENDER_NONE,
    GENDER_NON_BINARY,
    GENDER_QUEER,
    GENDER_TRANS_FEMALE,
    GENDER_TRANS_MALE,
    GENDER_TWO_SPIRIT
  ]

  GENDER_IDENTIFY_OPTIONS = [
    ["Not Stated", GENDER_NONE],
    ["Cis-Female", GENDER_CIS_FEMALE],
    ["Cis-Male", GENDER_CIS_MALE],
    ["Female", GENDER_FEMALE],
    ["Male", GENDER_MALE],
    ["Non-Binary", GENDER_NON_BINARY],
    ["Gender Fluid", GENDER_FLUID],
    ["Gender Queer", GENDER_QUEER],
    ["Trans-Female", GENDER_TRANS_FEMALE],
    ["Trans-Male", GENDER_TRANS_MALE],
    ["Two Spirit", GENDER_TWO_SPIRIT],
    ["Something Else", GENDER_CUSTOM]
  ]

  GENDER_IDENTITY_LABELS = options_to_labels_hash(GENDER_IDENTIFY_OPTIONS)
end
