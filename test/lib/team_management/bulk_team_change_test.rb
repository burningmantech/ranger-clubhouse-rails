# frozen_string_literal: true

require "test_helper"

class TeamManagement::BulkTeamChangeTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)         # TestRanger, active
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)
    Current.person = @admin

    @team = teams(:dirt_team)
    # team_category defaults to "public" in the schema, so every one of these
    # says which it is: a position created without it is the one kind this page
    # never moves.
    # Created in reverse alphabetical order on purpose: with the titles ascending
    # they would also be in id order, and an unordered query would look sorted.
    @optional = team_position("Dirt Sweeper", Position::TEAM_CATEGORY_OPTIONAL)
    @recommended = team_position("Dirt Patrol", Position::TEAM_CATEGORY_ALL_MEMBERS)
    @open = team_position("Dirt Open House", Position::TEAM_CATEGORY_PUBLIC)

    @member = person(:auditor_ranger)       # AuditorTest -- joined below
    @newcomer = person(:retired_ranger)     # RetiredRanger -- no membership
    PersonTeam.create!(team_id: @team.id, person_id: @member.id)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ------------------------------------------------------------- classifying

  test "a callsign matching no one is a problem" do
    change = build("NotAPerson", grant: true)

    assert_equal %i[not_found], verdicts(change)
    assert_equal "NotAPerson", change.problems.first.raw,
                 "the reader needs the line they typed to find the typo"
  end

  test "a locked status cannot be changed in either direction" do
    deceased = person(:deceased_ranger)
    PersonTeam.create!(team_id: @team.id, person_id: deceased.id)

    assert_equal %i[blocked_status], verdicts(build(deceased.callsign, grant: true))
    assert_equal %i[blocked_status], verdicts(build(deceased.callsign, grant: false))
  end

  test "past prospective is blocked alongside the locked statuses" do
    assert_equal %i[blocked_status], verdicts(build(person(:past_prospective_ranger).callsign, grant: true))
  end

  # Re-running a list is the ordinary case, not a failure.
  test "granting a team someone is already on is unchanged, not an error" do
    change = build(@member.callsign, grant: true)

    assert_equal %i[already_granted], verdicts(change)
    assert_equal 1, change.skipping.size
    assert_empty change.problems
  end

  test "revoking a team someone is not on is unchanged" do
    change = build(@newcomer.callsign, grant: false)

    assert_equal %i[already_revoked], verdicts(change)
    assert_equal 1, change.skipping.size
  end

  test "a grant and a revoke each name the people who will change" do
    assert_equal [@newcomer.id], build(@newcomer.callsign, grant: true).changing.map { |e| e.person.id }
    assert_equal [@member.id], build(@member.callsign, grant: false).changing.map { |e| e.person.id }
  end

  test "blank, whitespace and punctuation-only lines are dropped" do
    change = build("\n  \n#{@newcomer.callsign}\n---\n***\n", grant: true)

    assert_equal %i[grant], verdicts(change)
  end

  test "capitalisation and punctuation do not matter" do
    change = build(" re-TIRED ranger! ", grant: true)

    assert_equal [@newcomer.id], change.changing.map { |e| e.person.id }
  end

  test "the same person listed twice is acted on once" do
    change = build("#{@newcomer.callsign}\n#{@newcomer.callsign.downcase}", grant: true)

    assert_equal %i[grant duplicate], verdicts(change)
    assert_equal 1, change.changing.size
  end

  # Every role the team and its positions carry would land on the actor, which
  # is the one grant no one else reviews.
  test "the actor cannot change their own memberships" do
    change = build(@admin.callsign, grant: true)

    assert_equal %i[self_change], verdicts(change)
    assert_empty change.changing
  end

  # callsign_normalized carries no unique index, so two callsigns can normalize
  # alike. Refused rather than landing on whichever row came back last.
  test "a callsign matching two people is a problem, not a guess" do
    person(:alpha_ranger).update!(callsign: "#{@newcomer.callsign}!")

    change = build(@newcomer.callsign, grant: true)

    assert_equal %i[ambiguous], verdicts(change)
    assert_empty change.changing
  end

  test "entries stay in the order they were typed" do
    change = build("No one\n#{@newcomer.callsign}\n#{@member.callsign}", grant: true)

    assert_equal %i[not_found grant already_granted], verdicts(change)
  end

  # --------------------------------------------------- the positions that move

  # The asymmetry upstream draws: joining hands over only the Recommended
  # positions, because an Optional one is the member's own choice. Leaving takes
  # both. A Public position belongs to the whole organization either way.
  test "a grant moves only the Recommended positions" do
    assert_equal [@recommended.id], build(@newcomer.callsign, grant: true).position_ids
  end

  test "a revoke moves the Recommended and Optional positions" do
    assert_equal [@recommended.id, @optional.id].sort,
                 build(@member.callsign, grant: false).position_ids.sort
  end

  test "a public position never moves" do
    assert_not_includes build(@member.callsign, grant: false).position_ids, @open.id
  end

  # The preview and the confirm dialog both render these through to_sentence, so
  # the order is what the reader checks the operation against. Asserted against
  # the literal expected list rather than `titles.sort == titles`, which passes
  # on an empty array and on any list that happens to arrive sorted.
  test "moved positions come back in title order for the preview" do
    titles = build(@member.callsign, grant: false).moved_positions.map(&:title)

    assert_equal ["Dirt Patrol", "Dirt Sweeper"], titles
  end

  # ------------------------------------------------------------------ apply

  test "apply! adds the membership, grants the Recommended positions, and logs the upstream reason" do
    change = build(@newcomer.callsign, grant: true)

    assert_difference -> { PersonTeam.where(team_id: @team.id).count } => 1,
                      -> { PersonPosition.where(person_id: @newcomer.id).count } => 1 do
      outcome = change.apply!

      assert_equal [@newcomer.id], outcome.changed.map { |e| e.person.id }
      assert_not outcome.failed?
    end

    assert_equal [@recommended.id], PersonPosition.where(person_id: @newcomer.id).pluck(:position_id)
    assert_equal "bulk team grant",
                 ActionLog.where(event: "person-team-add", target_person_id: @newcomer.id).last.message
  end

  test "apply! removes the membership, revokes the Recommended and Optional positions, and logs" do
    PersonPosition.create!(person_id: @member.id, position_id: @recommended.id)
    PersonPosition.create!(person_id: @member.id, position_id: @optional.id)
    PersonPosition.create!(person_id: @member.id, position_id: @open.id)

    assert_difference -> { PersonTeam.where(team_id: @team.id).count } => -1,
                      -> { PersonPosition.where(person_id: @member.id).count } => -2 do
      build(@member.callsign, grant: false).apply!
    end

    assert_equal [@open.id], PersonPosition.where(person_id: @member.id).pluck(:position_id),
                 "a public position is open to everyone and survives leaving the team"
    assert_equal "bulk team revoke",
                 ActionLog.where(event: "person-team-remove", target_person_id: @member.id).last.message
  end

  # The membership is the whole operation when the team carries nothing.
  test "apply! grants a team with no Recommended positions without raising" do
    bare = teams(:operations_team)
    change = TeamManagement::BulkTeamChange.new(team: bare, grant: true, callsigns: @newcomer.callsign)

    assert_empty change.position_ids

    assert_difference -> { PersonTeam.where(team_id: bare.id).count } => 1,
                      -> { PersonPosition.count } => 0 do
      change.apply!
    end
  end

  test "apply! leaves a position the person already holds alone" do
    PersonPosition.create!(person_id: @newcomer.id, position_id: @recommended.id)

    assert_difference -> { PersonTeam.where(team_id: @team.id).count } => 1,
                      -> { PersonPosition.count } => 0 do
      build(@newcomer.callsign, grant: true).apply!
    end
  end

  # Someone who holds the team's positions but no membership row is left
  # entirely alone: this page moves memberships, and the orphaned grants are
  # Roster Management's to clean up.
  test "apply! does not strip positions from a non-member" do
    PersonPosition.create!(person_id: @newcomer.id, position_id: @recommended.id)

    assert_no_difference "PersonPosition.count" do
      assert_empty build(@newcomer.callsign, grant: false).apply!.changed
    end
  end

  test "apply! writes nothing for the skipped and problem lines" do
    change = build("No one\n#{@member.callsign}", grant: true)

    assert_no_difference ["PersonTeam.count", "PersonPosition.count"] do
      assert_empty change.apply!.changed
    end
  end

  # One bad row must not abort the batch: the manager confirmed a list, and a
  # partial write with no report of what failed is the worst outcome.
  test "apply! reports a failure and still finishes the rest of the batch" do
    other = person(:alpha_ranger)
    original = PersonPosition.method(:add_ids_to_person)
    doomed = @newcomer.id
    PersonPosition.define_singleton_method(:add_ids_to_person) do |person_id, ids, reason|
      raise AuthorizationError, "nope" if person_id == doomed

      original.call(person_id, ids, reason)
    end

    outcome = build("#{@newcomer.callsign}\n#{other.callsign}", grant: true).apply!

    assert_equal [other.id], outcome.changed.map { |e| e.person.id }
    assert_equal [@newcomer.id], outcome.failed.map { |e| e.person.id }
    assert_equal ["nope"], outcome.reasons
  ensure
    PersonPosition.define_singleton_method(:add_ids_to_person, original)
  end

  # The membership and its positions are one change: a failure half way through
  # must not leave someone on the roster holding nothing, or holding positions
  # with no membership to explain them.
  test "apply! rolls the membership back when the position grant fails" do
    original = PersonPosition.method(:add_ids_to_person)
    PersonPosition.define_singleton_method(:add_ids_to_person) do |*|
      raise AuthorizationError, "nope"
    end

    assert_no_difference "PersonTeam.count" do
      outcome = build(@newcomer.callsign, grant: true).apply!

      assert_equal [@newcomer.id], outcome.failed.map { |e| e.person.id }
    end
  ensure
    PersonPosition.define_singleton_method(:add_ids_to_person, original)
  end

  private

  def team_position(title, category)
    Position.create!(title:, team_id: @team.id, active: true, team_category: category)
  end

  def build(callsigns, grant:)
    TeamManagement::BulkTeamChange.new(team: @team, grant:, callsigns:)
  end

  def verdicts(change) = change.entries.map(&:verdict)
end
