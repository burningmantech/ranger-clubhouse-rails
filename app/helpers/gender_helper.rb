# frozen_string_literal: true

module GenderHelper
  include Gender

  def gender_format(person)
    case person.gender_identity
    when GENDER_CUSTOM
      person.gender_custom.present? ? person.gender_custom : "Not specified"
    when GENDER_NONE, "", nil
      "Not specified"
    else
      GENDER_IDENTITY_LABELS[person.gender_identity]
    end
  end
end
