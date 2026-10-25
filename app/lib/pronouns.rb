# frozen_string_literal: true

module Pronouns
  extend OptionsLabels

  PRONOUNS_FEMALE_LABEL = "She / Her / Hers"
  PRONOUNS_MALE_LABEL = "He / Him / His"
  NEUTRAL_LABEL = "They / Them / Their"

  PRONOUNS_FEMALE = "female"
  PRONOUNS_MALE = "male"
  PRONOUNS_NEUTRAL = "neutral"
  PRONOUNS_CUSTOM = "custom"

  PRONOUN_OPTIONS = [
    ["Not stated", ""],
    [PRONOUNS_FEMALE_LABEL, PRONOUNS_FEMALE],
    [PRONOUNS_MALE_LABEL, PRONOUNS_MALE],
    [NEUTRAL_LABEL, PRONOUNS_NEUTRAL],
    ["Something else", PRONOUNS_CUSTOM]
  ].freeze

  PRONOUN_LABELS = options_to_labels_hash(PRONOUN_OPTIONS)
end
