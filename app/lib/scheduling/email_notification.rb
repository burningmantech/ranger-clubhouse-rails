# frozen_string_literal: true

module Scheduling::EmailNotification
  TRAINER_POSITION_IDS = Position::TRAINERS.values.flatten.uniq.freeze

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

  # A trainer joined or left a trainer shift. Each session that shift teaches,
  # and that has a lead trainer other than that person, tells its leads. Queued
  # with a wait, and the roster is read again then: see TrainerRosterChangeJob.
  #
  # @param slot [Slot] the slot just joined or left; only a trainer slot matters
  # @param person_id [Integer]
  # @param change [String] TrainerRosterChangeJob::ADDED or ::REMOVED
  # @param reason [String, nil] why a sweep removed them
  def handle_trainer_roster_change(slot, person_id, change, reason: nil)
    return unless TRAINER_POSITION_IDS.include?(slot.position_id)

    session_position_ids = Position::TRAINERS.select { |_, trainer_ids| trainer_ids.include?(slot.position_id) }.keys
    sessions = Slot.for_position(session_position_ids).for_year(slot.begins_year)
                   .select { |session| Training::SessionList.trainer_slot_match?(session, slot) }

    sessions.each do |session|
      next if session.has_ended
      next unless TrainerStatus.where(slot_id: session.id, is_lead: true).where.not(person_id:).exists?

      TrainerRosterChangeJob.set(wait: 5.minutes)
                            .perform_later(session, slot, person_id, change, Current.person_id, reason)
    end
  end
end
