# frozen_string_literal: true

require "test_helper"

class TeamManagement::BulkPositionChangeTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)         # TestRanger, active
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)
    Current.person = @admin

    @team = teams(:dirt_team)
    @position = Position.create!(title: "Dirt Patrol", team_id: @team.id, active: true)

    @holder = person(:auditor_ranger)       # AuditorTest -- granted below
    @newcomer = person(:retired_ranger)     # RetiredRanger -- holds nothing
    PersonPosition.create!(person_id: @holder.id, position_id: @position.id)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ------------------------------------------------------------- classifying

  test "a callsign matching no one is a problem" do
    change = build("NotAPerson", grant: true)

    assert_equal %i[not_found], verdicts(change)
    assert_equal 1, change.problems.size
    assert_equal "NotAPerson", change.problems.first.raw,
                 "the reader needs the line they typed to find the typo"
  end

  test "a locked status cannot be changed in either direction" do
    deceased = person(:deceased_ranger)
    PersonPosition.create!(person_id: deceased.id, position_id: @position.id)

    assert_equal %i[blocked_status], verdicts(build(deceased.callsign, grant: true))
    assert_equal %i[blocked_status], verdicts(build(deceased.callsign, grant: false))
  end

  test "past prospective is blocked alongside the locked statuses" do
    change = build(person(:past_prospective_ranger).callsign, grant: true)

    assert_equal %i[blocked_status], verdicts(change)
  end

  test "granting a position someone already holds is unchanged, not an error" do
    change = build(@holder.callsign, grant: true)

    assert_equal %i[already_granted], verdicts(change)
    assert_equal 1, change.skipping.size
    assert_empty change.problems, "re-running a list is the ordinary case, not a failure"
  end

  test "revoking a position someone does not hold is unchanged" do
    change = build(@newcomer.callsign, grant: false)

    assert_equal %i[already_revoked], verdicts(change)
    assert_equal 1, change.skipping.size
  end

  test "a grant and a revoke each name the people who will change" do
    assert_equal [@newcomer.id], build(@newcomer.callsign, grant: true).changing.map { |e| e.person.id }
    assert_equal [@holder.id], build(@holder.callsign, grant: false).changing.map { |e| e.person.id }
  end

  test "blank and whitespace-only lines are dropped" do
    change = build("\n  \n#{@newcomer.callsign}\n\n", grant: true)

    assert_equal 1, change.entries.size
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

  # The actor's own callsign is the one grant no one else reviews.
  test "the actor cannot change their own positions" do
    change = build(@admin.callsign, grant: true)

    assert_equal %i[self_change], verdicts(change)
    assert_empty change.changing
  end

  # A repeated typo is one problem, not one per line: the count the preview
  # shows is the number of edits the reader has to make.
  test "a repeated problem line is counted once" do
    change = build("No one\nNo one", grant: true)

    assert_equal %i[not_found duplicate], verdicts(change)
    assert_equal 1, change.problems.size
  end

  test "a punctuation-only separator line is dropped, not reported as missing" do
    change = build("#{@newcomer.callsign}\n---\n***", grant: true)

    assert_equal %i[grant], verdicts(change)
  end

  # callsign_normalized carries no unique index, so two callsigns can normalize
  # alike. Refused rather than landing on whichever row came back last.
  test "a callsign matching two people is a problem, not a guess" do
    twin = person(:alpha_ranger)
    twin.update!(callsign: "#{@newcomer.callsign}!")

    change = build(@newcomer.callsign, grant: true)

    assert_equal %i[ambiguous], verdicts(change)
    assert_empty change.changing
  end

  test "entries stay in the order they were typed" do
    change = build("No one\n#{@newcomer.callsign}\n#{@holder.callsign}", grant: true)

    assert_equal %i[not_found grant already_granted], verdicts(change)
  end

  # ------------------------------------------------------------------ apply

  test "apply! grants the position and logs the upstream reason" do
    change = build(@newcomer.callsign, grant: true)

    assert_difference "PersonPosition.where(position_id: @position.id).count", 1 do
      outcome = change.apply!

      assert_equal [@newcomer.id], outcome.changed.map { |e| e.person.id }
      assert_not outcome.failed?
    end

    log = ActionLog.where(event: "person-position-add", target_person_id: @newcomer.id).last

    assert_equal "bulk position grant", log.message
  end

  test "apply! revokes the position and logs the upstream reason" do
    change = build(@holder.callsign, grant: false)

    assert_difference "PersonPosition.where(position_id: @position.id).count", -1 do
      change.apply!
    end

    log = ActionLog.where(event: "person-position-remove", target_person_id: @holder.id).last

    assert_equal "bulk position revoke", log.message
  end

  test "apply! writes nothing for the skipped and problem lines" do
    change = build("No one\n#{@holder.callsign}", grant: true)

    assert_no_difference "PersonPosition.count" do
      assert_empty change.apply!.changed
    end
  end

  test "apply! purges the cached role set" do
    purged = []
    original = RoleManager.method(:purge_person)
    RoleManager.define_singleton_method(:purge_person) do |person_id|
      purged << person_id
      original.call(person_id)
    end

    build(@newcomer.callsign, grant: true).apply!

    assert_includes purged, @newcomer.id
  ensure
    RoleManager.define_singleton_method(:purge_person, original)
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

  private

  def build(callsigns, grant:)
    TeamManagement::BulkPositionChange.new(position: @position, grant:, callsigns:)
  end

  def verdicts(change) = change.entries.map(&:verdict)
end
