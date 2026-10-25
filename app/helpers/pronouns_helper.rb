# frozen_string_literal: true

module PronounsHelper
  include Pronouns

  def pronouns_format(person, no_parens = false)
    pronouns = person.pronouns

    value =
      case pronouns
      when PRONOUNS_CUSTOM
        person.pronouns_custom
      when "", nil
        ""
      else
        PRONOUN_LABELS[pronouns]
      end

    return "" if value.blank?

    no_parens ? value : "(#{value})"
  end
end
