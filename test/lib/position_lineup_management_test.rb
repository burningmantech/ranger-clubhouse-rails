# frozen_string_literal: true

require "test_helper"

class PositionLineupManagementTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)
    Current.person = @admin

    @mentor = positions(:mentor_lead)
    @training = positions(:training_lead)
    @ood = positions(:ood_position)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "save creates a lineup with its members" do
    lineup = PositionLineup.new(description: "Mentor and Mentee")

    assert PositionLineupManagement.save(lineup, position_ids: [@mentor.id, @training.id])

    assert_equal [@mentor.id, @training.id].sort,
                 PositionLineupMember.where(position_lineup_id: lineup.id).pluck(:position_id).sort
  end

  test "save reports a missing description rather than raising" do
    lineup = PositionLineup.new

    assert_not PositionLineupManagement.save(lineup)
    assert lineup.errors[:description].any?
  end

  test "save adds and removes members to match what was submitted" do
    lineup = PositionLineup.create!(description: "Existing")
    PositionLineupMember.create!(position_lineup_id: lineup.id, position_id: @mentor.id)

    assert PositionLineupManagement.save(lineup, position_ids: [@training.id])

    assert_equal [@training.id], PositionLineupMember.where(position_lineup_id: lineup.id).pluck(:position_id)
  end

  test "save with an empty list empties the lineup" do
    lineup = PositionLineup.create!(description: "Existing")
    PositionLineupMember.create!(position_lineup_id: lineup.id, position_id: @mentor.id)

    assert PositionLineupManagement.save(lineup, position_ids: [])

    assert_empty PositionLineupMember.where(position_lineup_id: lineup.id)
  end

  test "save without a position list leaves the membership alone" do
    lineup = PositionLineup.create!(description: "Existing")
    PositionLineupMember.create!(position_lineup_id: lineup.id, position_id: @mentor.id)

    assert PositionLineupManagement.save(lineup)

    assert_equal [@mentor.id], PositionLineupMember.where(position_lineup_id: lineup.id).pluck(:position_id)
  end

  # position_lineup_member.position_id carries a UNIQUE index, and upstream adds
  # members with insertOrIgnore: checking a position that already sits in
  # another lineup writes nothing and still reports success. The reader is told
  # the lineup saved while the position they wanted is quietly missing from it.
  test "save refuses a position that already belongs to another lineup" do
    other = PositionLineup.create!(description: "Green Dot Pair")
    PositionLineupMember.create!(position_lineup_id: other.id, position_id: @mentor.id)
    lineup = PositionLineup.new(description: "Mine")

    assert_not PositionLineupManagement.save(lineup, position_ids: [@mentor.id])

    error = lineup.errors[:position_ids].join
    assert_includes error, @mentor.title, "the error must name the position"
    assert_includes error, "Green Dot Pair", "the error must name the lineup holding it"
    assert_empty PositionLineupMember.where(position_lineup_id: other.id, position_id: @training.id)
  end

  test "save keeps a position the lineup already holds" do
    lineup = PositionLineup.create!(description: "Existing")
    PositionLineupMember.create!(position_lineup_id: lineup.id, position_id: @mentor.id)

    assert PositionLineupManagement.save(lineup, position_ids: [@mentor.id, @training.id]),
           "a position already in THIS lineup is not a conflict"
  end

  test "save rejects a position id naming no position" do
    lineup = PositionLineup.new(description: "Mine")

    assert_not PositionLineupManagement.save(lineup, position_ids: [999_999])
    assert lineup.errors[:position_ids].any?
  end

  test "destroy removes the lineup and its membership but keeps the positions" do
    lineup = PositionLineup.create!(description: "Doomed")
    PositionLineupMember.create!(position_lineup_id: lineup.id, position_id: @mentor.id)

    assert PositionLineupManagement.destroy(lineup)

    assert_not PositionLineup.exists?(lineup.id)
    assert_empty PositionLineupMember.where(position_lineup_id: lineup.id)
    assert Position.exists?(@mentor.id), "deleting a lineup must not delete its positions"
  end
end
