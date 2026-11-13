# frozen_string_literal: true

module GenderHelper
  include Gender

  def gender_format(person)
    case person.gender_identity
    when GENDER_CUSTOM
      person.gender_custom.presence || "—"
    when GENDER_NONE, "", nil
      "—"
    else
      GENDER_IDENTITY_LABELS[person.gender_identity]
    end
  end
end
