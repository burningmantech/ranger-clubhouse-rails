# frozen_string_literal: true

class TrainingSignupMailer < ApplicationMailer
  def notify(slot:, person:)
    liquid_assigns[:slot] = {
      position_title: slot.position.title,
      description: slot.description,
      begins: slot.begins_human_format,
      url: slot.url.presence
    }

    mail(to: person.email, subject: liquid_subject)
  end
end
