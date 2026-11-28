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
    Role.create!(id: Role::ART_TRAINER_BASE | position.id, title: "ART Green Dot Interface")

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
    Role.create!(id: Role::EDIT_SWAG, title: "Edit Swag Records")
    Role.create!(id: Role::ART_TRAINER_BASE | position.id, title: "ART Green Dot Interface")
    Role.create!(id: Role::ART_GRADUATE_BASE | position.id, title: "ART Green Dot Graduate")

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
                 title: "ART Green Dot Interface")

    _named, groups = Role.catalog

    assert_equal "Position ##{Position::GREEN_DOT_TRAINING}", groups.first.first
  end

  test "a base carrying no position bits is not treated as a composed role" do
    assert_nil Role.new(id: Role::ART_TRAINER_BASE).art_position_id
  end

  # A permission filed twice would be drawn twice: two boxes with one id.
  test "GROUPS files no permission under two groups" do
    filed = Role::GROUPS.values.flatten

    assert_equal filed.uniq, filed
  end


  # The forms that grant permissions post the whole list, so a permission
  # grant_groups leaves out is revoked by the next save.
  test "grant_groups files every permission exactly once" do
    Role.delete_all
    art = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                           type: Position::TYPE_TRAINING, active: true)
    trainer = Position.create!(id: 2001, title: "Green Dot Trainer", type: Position::TYPE_TRAINING, active: true)
    Role.create!(id: Role::ADMIN, title: "Admin")
    # GROUPS lists EVENT_MANAGEMENT ahead of EDIT_SLOTS, and only a sort that
    # ignores case puts these two titles A to Z.
    Role.create!(id: Role::EVENT_MANAGEMENT, title: "Event Mgmt Year Round")
    Role.create!(id: Role::EDIT_SLOTS, title: "edit slots")
    Role.create!(id: 900, title: "Not Filed Anywhere")
    Role.create!(id: Role::ART_TRAINER_BASE, title: "A Base With No Position")
    Role.create!(id: Role::ART_GRADUATE_BASE | art.id, title: "ART Green Dot Graduate")
    Role.create!(id: Role::ART_TRAINER_BASE | art.id, title: "ART Green Dot Interface")
    # Composed from In-Person Training and from Alpha, neither of them an ART.
    Role.create!(id: Role::TRAINER_RESOURCE_MANAGEMENT_BASE | Position::TRAINING, title: "T.A. Resource Mgmt")
    Role.create!(id: Role::SURVEY_MANAGEMENT_BASE | Position::TRAINING, title: "In-Person Survey Mgmt")
    Role.create!(id: Role::SURVEY_MANAGEMENT_BASE | Position::ALPHA, title: "Alpha Survey Management")
    # Composed from a trainer position, which is no ART, and from a position that is gone.
    Role.create!(id: Role::ART_TRAINER_BASE | trainer.id, title: "Composed From a Trainer Position")
    Role.create!(id: Role::ART_TRAINER_BASE | 2002, title: "Composed From a Deleted Position")

    groups, art_groups = Role.grant_groups

    filed = (groups + art_groups).flat_map { |_title, permissions| permissions.map(&:id) }
    assert_equal Role.pluck(:id).sort, filed.sort

    # Groups keep the order GROUPS gives them, and one with nothing in it is left out.
    assert_equal ["General Event Operations", "In-Person Training", "Mentoring", "Shift / Timesheet Management", "System Administration", "Other", "Training"],
                 groups.map(&:first)
    titles = groups.to_h.transform_values { |permissions| permissions.map(&:title) }
    # Whatever is composed from In-Person Training or from Alpha sits with its
    # subject, so neither position can have a card of its own.
    assert_equal ["Alpha Survey Management"], titles["Mentoring"]
    assert_equal ["A Base With No Position", "Composed From a Deleted Position",
                  "Composed From a Trainer Position", "Not Filed Anywhere"], titles["Other"]

    # Only an ART has an entry of its own, its permissions in base order.
    assert_equal [["Green Dot Training", ["ART Green Dot Interface", "ART Green Dot Graduate"]]],
                 art_groups.map { |title, permissions| [title, permissions.map(&:title)] }
  end

  test "art_type_label is the type, or the whole title for a base the code does not name" do
    known = Role.new(id: Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, title: "ART Green Dot Interface")
    unknown = Role.new(id: 0x50000000 | Position::GREEN_DOT_TRAINING, title: "ART Green Dot Mystery")

    assert_equal "Interface", known.art_type_label
    assert_equal "ART Green Dot Mystery", unknown.art_type_label
  end

  test "grant_groups has no Other group when every named permission is filed" do
    Role.delete_all
    Role.create!(id: Role::ADMIN, title: "Admin")

    groups, art_groups = Role.grant_groups

    assert_equal ["System Administration"], groups.map(&:first)
    assert_empty art_groups
  end

  test "the two roles that confer admin access are protected from deletion" do
    assert Role.new(id: Role::ADMIN).protected_role?
    assert Role.new(id: Role::TECH_NINJA).protected_role?
    assert_not Role.new(id: Role::EDIT_SWAG).protected_role?
  end

  test "renaming a role is written to the audit log" do
    role = Role.create!(id: Role::EDIT_SWAG, title: "Edit Swag Records")
    ActionLog.delete_all

    role.update!(title: "Edit Swag")

    assert ActionLog.where(event: "role-update").exists?
  end
end
