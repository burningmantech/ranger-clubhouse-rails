# frozen_string_literal: true

# Emails a training session's lead trainers when another trainer joins or leaves
# its trainer roster.
#
# Held back a few minutes on purpose, like AlertWhenSignUpsEmptyJob: the roster
# is read again here, so someone who drops a shift and picks it straight back up
# sends nothing.
class TrainerRosterChangeJob < ApplicationJob
  ADDED = "added"
  REMOVED = "removed"

  # @param session_slot [Slot] the trainees' session
  # @param trainer_slot [Slot] the trainer shift that was joined or left
  # @param person_id [Integer] who joined or left
  # @param change [String] ADDED or REMOVED
  # @param actor_id [Integer, nil] who made the change
  # @param reason [String, nil] why a sweep removed them
  def perform(session_slot, trainer_slot, person_id, change, actor_id = nil, reason = nil)
    return if session_slot.has_ended

    training = Position.find(training_position_id(session_slot))
    groups = TrainingSession.new(session_slot, training).trainer_groups
    # A session lists only the first matching slot per trainer position.
    group = groups.find { |candidate| candidate.slot.id == trainer_slot.id }
    return unless group

    on_roster = group.trainers.any? { |trainer| trainer.person.id == person_id }
    return unless on_roster == (change == ADDED)

    person = Person.find_by(id: person_id)
    return unless person

    # Not the trainer themself, and not whoever made the change: both know.
    lead_emails = groups.flat_map(&:trainers)
                        .select { |trainer| trainer.is_lead && [person_id, actor_id].exclude?(trainer.person.id) }
                        .filter_map { |trainer| trainer.person.email.presence }
                        .uniq
    return if lead_emails.empty?

    TrainerRosterChangeMailer.with(sender_id: actor_id).notify(
      session_slot:,
      training:,
      change:,
      trainer: { callsign: person.callsign, position_title: group.position_title },
      trainers: roster_rows(groups, (person_id if change == ADDED)),
      lead_emails:,
      changed_by: (Person.find_by(id: actor_id)&.callsign if actor_id && actor_id != person_id),
      reason:
    ).deliver_now
  end

  private

  # HQ refresher sessions are managed from HQ Full Training's pages
  # (Training.session_position_ids).
  def training_position_id(session_slot)
    if session_slot.position_id == Position::HQ_REFRESHER_TRAINING
      Position::HQ_FULL_TRAINING
    else
      session_slot.position_id
    end
  end

  def roster_rows(groups, added_person_id)
    groups.flat_map do |group|
      group.trainers.map do |trainer|
        {
          callsign: trainer.person.callsign,
          position_title: group.position_title,
          is_lead: trainer.is_lead,
          is_changed: trainer.person.id == added_person_id
        }
      end
    end
  end
end
