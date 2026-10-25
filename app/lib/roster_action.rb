# frozen_string_literal: true

# What a Roster Management bulk action will do, and then the doing of it.
#
# One object answers both questions so the preview and the commit cannot
# disagree: the page a manager confirms is built from the same #changing and
# #skipping the apply then walks.
class RosterAction
  REMOVE_FROM_TEAM = "remove"
  GRANT_POSITION = "grant"
  REVOKE_POSITION = "revoke"
  TYPES = [REMOVE_FROM_TEAM, GRANT_POSITION, REVOKE_POSITION].freeze

  # A position action names a position; removing from the team does not.
  NEEDS_POSITION = [GRANT_POSITION, REVOKE_POSITION].freeze

  Outcome = Struct.new(:changed, :failed, :reasons, keyword_init: true) do
    def failed? = failed.any?
  end

  def self.type?(value) = TYPES.include?(value)

  # @param team [Team]
  # @param type [String] one of TYPES
  # @param people [Array<TeamMembershipReport::Member>] the selected rows
  # @param position [Position, nil] the position a grant or revoke names
  # @param revocable_position_ids [Array<Integer>] what a team removal strips
  def initialize(team:, type:, people:, revocable_position_ids:, position: nil)
    @team = team
    @type = type
    @people = people
    @position = position
    @revocable_position_ids = revocable_position_ids
  end

  attr_reader :team, :type, :people, :position

  def remove_from_team? = type == REMOVE_FROM_TEAM

  def grant? = type == GRANT_POSITION

  # The people this action actually changes. Someone who already holds the
  # position being granted, or does not hold the one being revoked, is listed
  # separately rather than counted as changed -- the preview has to be honest
  # about how many rows will move.
  def changing = @changing ||= people.select { |person| changes?(person) }

  def skipping = @skipping ||= people - changing

  # Why the skipped rows are skipped, in one phrase for the preview.
  def skip_reason
    case type
    when GRANT_POSITION then "already holds #{position.title}"
    when REVOKE_POSITION then "does not hold #{position.title}"
    else "nothing to remove -- not a member and holds none of the team's positions"
    end
  end

  # The positions this action grants or revokes, which decides whether it would
  # move a role grant the actor may not confer.
  def position_ids
    remove_from_team? ? @revocable_position_ids : [position.id]
  end

  # The position ids a given person actually loses or gains, for the preview's
  # per-row detail. Titles are the view's business.
  def effect_on(person)
    return [position.id] unless remove_from_team?

    person.grants.keys.intersection(@revocable_position_ids)
  end

  # Each person is applied in their own transaction, so a failure part way
  # through cannot leave one of them half-changed, and the rest of the batch is
  # still attempted.
  def apply!(reason:)
    changed = []
    failed = []
    reasons = []

    changing.each do |person|
      ActiveRecord::Base.transaction { apply_to(person, reason) }
      # Team and position grants both carry roles, and the role set is cached
      # per person with no expiry.
      RoleManager.purge_person(person.id)
      changed << person
    rescue StandardError => e
      Rails.logger.error("Roster #{type} failed for person #{person.id}: #{e.class}: #{e.message}")
      failed << person
      reasons << e.message
    end

    Outcome.new(changed:, failed:, reasons: reasons.uniq)
  end

  private

  def changes?(person)
    case type
    when GRANT_POSITION then person.grant(position.id).nil?
    when REVOKE_POSITION then person.grant(position.id).present?
    else person.member? || person.grants.keys.intersect?(@revocable_position_ids)
    end
  end

  def apply_to(person, reason)
    case type
    when GRANT_POSITION
      PersonPosition.add_ids_to_person(person.id, [position.id], reason)
    when REVOKE_POSITION
      PersonPosition.remove_ids_from_person(person.id, [position.id], reason)
    else
      PersonPosition.remove_ids_from_person(person.id, @revocable_position_ids, reason)
      PersonTeam.remove_person(team.id, person.id, reason)
    end
  end
end
