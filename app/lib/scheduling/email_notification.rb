# frozen_string_literal: true

module Scheduling::EmailNotification
  module_function

  # person_id is whoever just left the shift. The alert names them so the team
  # reading it knows who to ask, so it has to travel with the slot.
  def handle_empty_signups_alerts(slot, person_id)
    return if slot.signed_up.positive?

    if slot.position.alert_when_no_trainers
      trainee_slot = Slot.find_by(trainer_slot_id: slot.id)
      if trainee_slot&.signed_up&.positive?
        AlertWhenSignUpsEmptyJob.set(wait: 5.minutes).perform_later(slot.position, slot, person_id, trainee_slot)
      end
    end

    if slot.position.alert_when_becomes_empty && Setting.get_value(Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED)
      AlertWhenSignUpsEmptyJob.set(wait: 5.minutes).perform_later(slot.position, slot, person_id)
    end
  end
end
