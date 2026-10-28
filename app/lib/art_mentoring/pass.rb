# frozen_string_literal: true

# What passing an ART mentee can also do (ruled 2026-10-21): add them to the
# training's team with the team's Recommended positions -- a membership never
# moves alone, as on Bulk Team Grant / Revoke -- and revoke the training's
# mentee positions. A graduate-role holder is offered both when a pass is
# recorded, and chooses.
#
# The mentee positions revoked are the ART mentee position the pages pair on
# shift and every one the training's graduation granted (Training.
# mentee_position_ids: Green Dot Mentee and Sanctuary Mentee), so a passed
# mentee leaves Current Mentees whole (2026-10-22). Nobody whose status keeps
# them off every team (Bulk Team Grant's BLOCKED_STATUSES) is added to one.
class ArtMentoring::Pass
  REASON = "ART mentoring pass"

  # What a pass can still do for one mentee: `join` is false once they belong
  # to the team -- or their status bars them -- and `revoke` lists the mentee
  # positions they still hold.
  Offer = Data.define(:person, :join, :revoke) do
    def any? = join || revoke.any?
  end

  # What a pass did for one mentee: whether they joined, and the mentee
  # positions revoked.
  Grant = Data.define(:joined, :revoked) do
    def any? = joined || revoked.any?
    def merge(other) = Grant.new(joined: joined || other.joined, revoked: revoked | other.revoked)
  end

  # What the roster asks before a save, by timesheet id: `offers` for a
  # graduate-role holder (#offers), and `without_mentor`, each mentee passed
  # with no mentor selected, whoever records it (owner, 2026-10-28), to their
  # person. `granting` is a press of Grant Team Positions, whose pass is
  # already recorded.
  Question = Data.define(:offers, :without_mentor, :granting) do
    def any? = offers.any? || without_mentor.any?
    def people = without_mentor.merge(offers.transform_values(&:person))
    # Record Pass but Not Promote: a pass to record with something to promote.
    def promotable? = !granting && offers.any?
    # Promote Without a Verdict: something to promote for a pass with no mentor.
    def promotable_without_mentor? = offers.keys.intersect?(without_mentor.keys)
  end

  attr_reader :team, :mentee_position

  # @param training [Position] an ART mentoring training
  # @param mentee_position [Position, nil] its ART mentee position
  def initialize(training, mentee_position)
    @training = training
    @team = training.team
    @mentee_position = mentee_position
  end

  # The team's Recommended positions, granted with the membership.
  def recommended_positions
    @recommended_positions ||= team ? TeamManagement::BulkTeamChange.positions_for(team, grant: true) : []
  end

  # The mentee positions a pass revokes, in title order.
  def revoked_positions
    @revoked_positions ||= Position.where(id: [mentee_position&.id, *Training.mentee_position_ids(@training)].compact)
                                   .order(:title).to_a
  end

  # Whether this person's status lets a pass add them to a team.
  def joinable?(person) = TeamManagement::BulkTeamChange::BLOCKED_STATUSES.exclude?(person.status)

  # One offer per person: two entries of one mentee on a shift share one
  # answer.
  # @param entries [Array<Timesheet>] mentee entries, each with its person
  # @return [Hash{Integer => Offer}] by timesheet id, for the entries a pass
  #   can still do something for
  def offers(entries)
    return {} if entries.empty?

    entries = entries.uniq(&:person_id)
    ids = entries.map(&:person_id)
    members = team ? PersonTeam.where(team_id: team.id, person_id: ids).pluck(:person_id).to_set : Set.new
    by_id = revoked_positions.index_by(&:id)
    held = PersonPosition.where(position_id: by_id.keys, person_id: ids).pluck(:person_id, :position_id)
                         .group_by(&:first).transform_values { |pairs| pairs.map { |_person, id| by_id[id] } }

    entries.to_h do |entry|
      join = team.present? && !members.include?(entry.person_id) && joinable?(entry.person)
      [entry.id, Offer.new(person: entry.person, join:, revoke: held.fetch(entry.person_id, []))]
    end.select { |_id, offer| offer.any? }
  end

  # Do the chosen parts for one mentee. Not a transaction of its own: the
  # roster's save wraps it with the walk it belongs to, so a refused grant
  # (PersonTeam and PersonPosition raise AuthorizationError on a team or
  # position conferring Admin or Tech Ninja) records nothing at all.
  # @return [Grant] what was done
  def apply!(person, join:, revoke:)
    person_id = person.id
    joined = join && team && joinable?(person) && !PersonTeam.have_team(team.id, person_id)
    if joined
      PersonTeam.add_person(team.id, person_id, REASON)
      PersonPosition.add_ids_to_person(person_id, recommended_positions.map(&:id), REASON)
    end

    held_ids = revoke ? PersonPosition.where(person_id:, position_id: revoked_positions.map(&:id)).pluck(:position_id) : []
    # Also drops their future sign-ups for them (remove_ids_from_person).
    PersonPosition.remove_ids_from_person(person_id, held_ids, REASON) if held_ids.any?

    Grant.new(joined: joined || false, revoked: revoked_positions.select { |position| held_ids.include?(position.id) })
  end
end
