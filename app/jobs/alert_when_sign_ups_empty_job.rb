# frozen_string_literal: true

# Tells a team that no one is left signed up for one of their shifts.
#
# Held back a few minutes on purpose: someone dropping a shift and picking it
# straight back up is common, and the counts are read again here so that pair of
# actions stays quiet instead of sending an alert no one needed.
class AlertWhenSignUpsEmptyJob < ApplicationJob
  def perform(position, slot, person_id, trainee_slot = nil)
    return if position.contact_email.blank?

    slot.reload
    trainee_slot&.reload
    return if slot.signed_up.positive?
    return if trainee_slot && !trainee_slot.signed_up.positive?

    AlertWhenSignUpsEmptyMailer.notify(
      position: position,
      slot: slot,
      person: Person.find_by(id: person_id),
      trainee_signups: trainee_slot&.signed_up
    ).deliver_now
  end
end
