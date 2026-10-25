# frozen_string_literal: true

require "test_helper"

# Role: the composed per-position role bases and the titles they read as.
class RoleTest < ActiveSupport::TestCase
  # The rows for this base were minted by the Laravel side of the shared
  # database, so the constant is not free to change.
  test "the resource management base matches the rows already in the database" do
    assert_equal 0x40000000, Role::TRAINER_RESOURCE_MANAGEMENT_BASE
    assert_equal Role::TRAINER_RESOURCE_MANAGEMENT_BASE,
                 Role::TRAINER_RESOURCE_MANAGEMENT_BASE & Role::ROLE_BASE_MASK
  end

  test "a composed role reads as its suffix and its position" do
    role = Role.new(id: Role::TRAINER_RESOURCE_MANAGEMENT_BASE | Position::GREEN_DOT_TRAINING)

    assert_equal "Resrc Mgmt", role.art_role_title
  end

  test "create_art_roles mints the resource management role alongside the others" do
    position = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                type: Position::TYPE_TRAINING, active: true)

    added, existing = Role.create_art_roles(position.id)

    assert_empty existing
    assert_includes added.map { |role| role[:id] },
                    Role::TRAINER_RESOURCE_MANAGEMENT_BASE | position.id
    assert_includes added.map { |role| role[:title] }, "ART Green Dot Resrc Mgmt"
  end

  # find_by rather than find: a position granted the older three roles but not
  # the fourth has to be able to acquire it.
  test "create_art_roles fills in a missing role without raising" do
    position = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                type: Position::TYPE_TRAINING, active: true)
    Role.create!(id: Role::ART_TRAINER_BASE | position.id, title: "ART Green Dot Interface",
                 new_user_eligible: false)

    added, existing = Role.create_art_roles(position.id)

    assert_equal ["ART Green Dot Interface"], existing.map { |role| role[:title] }
    assert_includes added.map { |role| role[:id] },
                    Role::TRAINER_RESOURCE_MANAGEMENT_BASE | position.id
  end

  test "art_position_id reads the position out of a composed role and nothing out of the rest" do
    composed = Role.new(id: Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)

    assert_equal Position::GREEN_DOT_TRAINING, composed.art_position_id
    assert_nil Role.new(id: Role::EDIT_SWAG).art_position_id
  end

  test "catalog groups composed roles under their position and leaves the rest alone" do
    Role.delete_all
    position = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                type: Position::TYPE_TRAINING, active: true)
    Role.create!(id: Role::EDIT_SWAG, title: "Edit Swag Records", new_user_eligible: false)
    Role.create!(id: Role::ART_TRAINER_BASE | position.id, title: "ART Green Dot Interface",
                 new_user_eligible: false)
    Role.create!(id: Role::ART_GRADUATE_BASE | position.id, title: "ART Green Dot Graduate",
                 new_user_eligible: false)

    named, groups = Role.catalog

    assert_equal ["Edit Swag Records"], named.map(&:title)
    assert_equal 1, groups.size

    title, roles = groups.first
    assert_equal "Green Dot Training", title
    # Ordered by the base each was built from, so the same suffix sits in the
    # same place under every position.
    assert_equal ["ART Green Dot Interface", "ART Green Dot Graduate"], roles.map(&:title)
  end

  test "catalog names a group after the position number when the position is gone" do
    Role.delete_all
    Position.where(id: Position::GREEN_DOT_TRAINING).delete_all
    Role.create!(id: Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING,
                 title: "ART Green Dot Interface", new_user_eligible: false)

    _named, groups = Role.catalog

    assert_equal "Position ##{Position::GREEN_DOT_TRAINING}", groups.first.first
  end

  test "a base carrying no position bits is not treated as a composed role" do
    assert_nil Role.new(id: Role::ART_TRAINER_BASE).art_position_id
  end

  test "the two roles that confer admin access are protected from deletion" do
    assert Role.new(id: Role::ADMIN).protected_role?
    assert Role.new(id: Role::TECH_NINJA).protected_role?
    assert_not Role.new(id: Role::EDIT_SWAG).protected_role?
  end

  test "renaming a role is written to the audit log" do
    role = Role.create!(id: Role::EDIT_SWAG, title: "Edit Swag Records", new_user_eligible: false)
    ActionLog.delete_all

    role.update!(title: "Edit Swag")

    assert ActionLog.where(event: "role-update").exists?
  end
end
