# frozen_string_literal: true

# Position lineup administration: the save and destroy rules the Ember
# admin/positions lineup tab got from the Laravel PositionLineup model's boot()
# hooks and PositionLineupMember::updateMembership.
#
# Lives here rather than on PositionLineup because the model is frozen for the
# translation.
module PositionLineupManagement
  # Ember caps the description input at 100. The column is a plain string, so
  # the shorter of the two governs.
  DESCRIPTION_MAX = 100
  SAVE_REASON = "Position lineup edit"
  DELETE_REASON = "Position lineup deletion"

  module_function

  # Validate and persist, syncing the lineup's membership.
  #
  # position_ids is nil when the form never offered the field, and [] when
  # every box was cleared -- only the latter empties the lineup.
  def save(lineup, position_ids: nil)
    desired = IdList.parse(position_ids) if position_ids
    return false unless valid?(lineup, desired)

    creating = lineup.new_record?

    ApplicationRecord.transaction do
      lineup.save!
      update_membership(lineup.id, desired) if desired
      ActionLog.record(Current.person, creating ? "position-lineup-create" : "position-lineup-update",
                       SAVE_REASON, { position_lineup_id: lineup.id, description: lineup.description,
                                      position_ids: desired })
    end

    # Sign-up pages read the lineup to decide which positions are shown
    # together, and that lookup is cached.
    Rails.cache.clear
    true
  rescue ActiveRecord::RecordNotUnique
    # validate_positions reads position_lineup_member before the transaction
    # opens, so two admins claiming the same position at the same moment both
    # pass it and the loser's insert hits the UNIQUE index. Re-run the check now
    # that the winner has committed: it names the position and the lineup that
    # took it, which is the message the reader would have got a second earlier.
    validate_positions(lineup, desired) if desired
    if lineup.errors.empty?
      lineup.errors.add(:base, "Another admin changed a lineup at the same moment. Check the positions and save again.")
    end
    false
  end

  def destroy(lineup)
    position_lineup_id = lineup.id
    description = lineup.description

    ApplicationRecord.transaction do
      # Cleared explicitly rather than through dependent: :destroy so the row
      # removal cannot depend on the composite-key association behaving.
      PositionLineupMember.where(position_lineup_id:).delete_all
      lineup.delete
      ActionLog.record(Current.person, "position-lineup-delete", DELETE_REASON,
                       { position_lineup_id:, description: })
    end

    Rails.cache.clear
    true
  end

  # The add/remove diff upstream runs in PositionLineupMember::updateMembership.
  def update_membership(position_lineup_id, position_ids)
    existing = PositionLineupMember.where(position_lineup_id:).pluck(:position_id)

    (position_ids - existing).each do |position_id|
      PositionLineupMember.create!(position_lineup_id:, position_id:)
    end

    removed = existing - position_ids
    PositionLineupMember.where(position_lineup_id:, position_id: removed).delete_all if removed.any?
  end

  def valid?(lineup, desired_positions = nil)
    lineup.errors.clear
    lineup.valid?

    if lineup.description.present? && lineup.description.length > DESCRIPTION_MAX
      lineup.errors.add(:description, "The description must be #{DESCRIPTION_MAX} characters or fewer.")
    end

    validate_positions(lineup, desired_positions) if desired_positions

    lineup.errors.empty?
  end

  # position_lineup_member.position_id carries a UNIQUE index: a position
  # belongs to at most one lineup. Upstream adds members with insertOrIgnore,
  # so checking a position that already sits in another lineup writes nothing
  # and reports success -- the reader is told the lineup was saved while the
  # position they wanted is quietly missing from it. Reported here instead.
  def validate_positions(lineup, desired_positions)
    unknown = desired_positions - Position.where(id: desired_positions).pluck(:id)
    lineup.errors.add(:position_ids, "The positions include #{unknown.sort.join(", ")}, which name no position.") if unknown.any?

    taken = PositionLineupMember.where(position_id: desired_positions)
                                .where.not(position_lineup_id: lineup.id)
                                .pluck(:position_id, :position_lineup_id)
    return if taken.empty?

    titles = Position.titles_by_id(taken.map(&:first))
    lineups = PositionLineup.where(id: taken.map(&:last)).pluck(:id, :description).to_h
    conflicts = taken.map do |position_id, lineup_id|
      "#{titles[position_id]} (already in #{lineups[lineup_id] || "another lineup"})"
    end

    lineup.errors.add(:position_ids,
                      "The lineup cannot include #{conflicts.sort.to_sentence}: a position belongs to one lineup at a time.")
  end
end
