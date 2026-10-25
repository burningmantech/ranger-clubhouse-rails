# frozen_string_literal: true

require "test_helper"

# What a pass can also do (ArtMentoring::Pass, ruled 2026-10-21): join the
# training's team with its Recommended positions, and lose the mentee position.
class ArtMentoring::PassTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role
  include ArtMentoringTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 9, 2, 19, 0, 0)
    Current.reset
    setup_art_mentoring
    @dirt = recommended_position("Dirt - Green Dot")
    @sanctuary = recommended_position("Green Dot Sanctuary")
    @lead = Position.create!(title: "Green Dot Lead", type: Position::TYPE_FRONTLINE, active: true,
                             team: @training.team, team_category: Position::TEAM_CATEGORY_OPTIONAL)
    @lodestar = create_person("Lodestar")
    hold_mentee_position(@lodestar)
    @pass = ArtMentoring::Pass.new(@training, @mentee_position)
  end

  teardown do
    Current.reset
    travel_back
  end

  def positions_held(person) = PersonPosition.where(person_id: person.id).pluck(:position_id).sort

  test "joining brings the team's Recommended positions, not its optional ones" do
    assert_equal ArtMentoring::Pass::Grant.new(joined: true, revoked: []), @pass.apply!(@lodestar, join: true, revoke: false)

    assert PersonTeam.exists?(team_id: @training.team_id, person_id: @lodestar.id)
    assert_equal [@dirt.id, @sanctuary.id, @mentee_position.id].sort, positions_held(@lodestar),
                 "the mentee position stays: revoking was not chosen"
  end

  test "revoking takes the mentee position and its future sign-ups" do
    future = mentee_shift(Time.zone.local(YEAR, 9, 3, 5, 45, 0))
    PersonSlot.create!(person_id: @lodestar.id, slot_id: future.id)

    assert_equal [@mentee_position], @pass.apply!(@lodestar, join: false, revoke: true).revoked

    assert_empty positions_held(@lodestar)
    assert_not PersonSlot.exists?(person_id: @lodestar.id, slot_id: future.id)
    assert_not PersonTeam.exists?(team_id: @training.team_id, person_id: @lodestar.id), "joining was not chosen"
  end

  test "a second pass for a member who no longer holds the mentee position does nothing" do
    @pass.apply!(@lodestar, join: true, revoke: true)

    assert_not @pass.apply!(@lodestar, join: true, revoke: true).any?
  end

  test "the offer says what a pass can still do for each mentee" do
    sheet = mentee_entry(@lodestar, Time.zone.local(YEAR, 9, 2, 17, 31, 0))

    offer = @pass.offers([sheet])[sheet.id]
    assert offer.join && offer.revoke.any?, "a mentee off the team still holding the position can gain both"

    @pass.apply!(@lodestar, join: true, revoke: true)
    assert_empty @pass.offers([sheet]), "a member without the mentee position has nothing left to gain"
  end

  test "a pass revokes every mentee position the training's graduation granted" do
    sanctuary_mentee = Position.create!(id: Position::SANCTUARY_MENTEE, title: "Sanctuary Mentee",
                                        type: Position::TYPE_FRONTLINE, active: true)
    PersonPosition.create!(person_id: @lodestar.id, position_id: sanctuary_mentee.id)
    pass = ArtMentoring::Pass.new(@training, @mentee_position)

    assert_equal ["Green Dot Mentee", "Sanctuary Mentee"], pass.revoked_positions.map(&:title)
    sheet = mentee_entry(@lodestar, Time.zone.local(YEAR, 9, 2, 17, 31, 0))
    assert_equal pass.revoked_positions, pass.offers([sheet])[sheet.id].revoke, "the offer names both, as held"
    assert_equal pass.revoked_positions, pass.apply!(@lodestar, join: false, revoke: true).revoked
    assert_empty positions_held(@lodestar)
  end

  test "a pass never adds someone whose status keeps them off every team" do
    @lodestar.update_column(:status, Person::RESIGNED)
    sheet = mentee_entry(@lodestar, Time.zone.local(YEAR, 9, 2, 17, 31, 0))

    offer = @pass.offers([sheet])[sheet.id]
    assert_not offer.join
    assert_equal [@mentee_position], offer.revoke

    assert_equal ArtMentoring::Pass::Grant.new(joined: false, revoked: [@mentee_position]),
                 @pass.apply!(@lodestar.reload, join: true, revoke: true)
    assert_not PersonTeam.exists?(team_id: @training.team_id, person_id: @lodestar.id)
  end

  test "two entries of one mentee on a shift get one offer" do
    first = mentee_entry(@lodestar, Time.zone.local(YEAR, 9, 2, 17, 31, 0), off_duty: Time.zone.local(YEAR, 9, 2, 18, 0, 0))
    again = mentee_entry(@lodestar, Time.zone.local(YEAR, 9, 2, 18, 10, 0))

    assert_equal [first.id], @pass.offers([first, again]).keys
  end

  # PersonTeam refuses a membership conferring Admin to anyone not an Admin;
  # the roster's save catches it and writes nothing (ArtMentoring::Assignment).
  test "a team conferring Admin is refused to a grantor without it" do
    ensure_role(Role::ADMIN, "Admin")
    TeamRole.create!(team_id: @training.team_id, role_id: Role::ADMIN)

    assert_raises(AuthorizationError) { @pass.apply!(@lodestar, join: true, revoke: false) }
  end
end
