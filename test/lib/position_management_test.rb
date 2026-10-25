# frozen_string_literal: true

require "test_helper"

class PositionManagementTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    ensure_role(Role::MENTOR, "Mentor")
    grant_role(@admin, Role::ADMIN)
    Current.person = @admin

    @position = positions(:ood_position)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ------------------------------------------------------------------- save

  test "save persists a valid position and writes an audit entry" do
    position = Position.new(title: "Test Frontline", type: Position::TYPE_FRONTLINE)

    assert_difference "ActionLog.where(event: 'position-create').count", 1 do
      assert PositionManagement.save(position)
    end

    assert position.persisted?
  end

  test "save reports a missing title rather than raising" do
    position = Position.new(type: Position::TYPE_FRONTLINE)

    assert_not PositionManagement.save(position)
    assert position.errors[:title].any?
  end

  # Both columns are NOT NULL, both are number fields that cast a cleared input
  # to nil, and the model validates them with allow_nil -- so without this the
  # save reached MariaDB and 500'd on a NotNullViolation.
  test "save reports a cleared minimum or hour cap rather than raising" do
    PositionManagement::NOT_NULL_NUMBERS.each_key do |column|
      position = Position.new(title: "ZZ Blank #{column}", type: Position::TYPE_FRONTLINE, column => nil)

      assert_not PositionManagement.save(position), "#{column} must not reach the database as NULL"
      assert position.errors[column].any?
    end
  end

  test "save rejects a team or position id naming no row" do
    position = Position.new(title: "ZZ Dangling", type: Position::TYPE_FRONTLINE,
                            team_id: 999_999, parent_position_id: 999_998)

    assert_not PositionManagement.save(position)
    assert position.errors[:team_id].any?
    assert position.errors[:parent_position_id].any?
  end

  # on_sl_report is the one nullable flag, and a checkbox always posts its hidden
  # "0". Saving an unrelated field must not rewrite NULL to false.
  test "save leaves a null shift-lead flag alone" do
    @position.update_column(:on_sl_report, nil)
    position = Position.find(@position.id)
    position.assign_attributes(title: "ZZ Renamed", on_sl_report: false)

    assert PositionManagement.save(position)
    assert_nil position.reload.on_sl_report
  end

  test "save still records a shift-lead flag the reader actually set" do
    @position.update_column(:on_sl_report, nil)
    position = Position.find(@position.id)
    position.on_sl_report = true

    assert PositionManagement.save(position)
    assert position.reload.on_sl_report
  end

  # The model owns the three cross-field rules; the service used to repeat them,
  # so every one of them reached the reader twice in two different wordings.
  test "a cross-field conflict is reported once" do
    @position.require_training_for_roles = true
    @position.training_position_id = nil

    assert_not PositionManagement.save(@position)
    assert_equal 1, @position.errors[:require_training_for_roles].size
  end

  # The three cross-field rules upstream enforces in Position::save(). Each
  # describes a position the rest of the Clubhouse cannot act on.
  test "save rejects requiring training for roles with no training position" do
    @position.assign_attributes(require_training_for_roles: true, training_position_id: nil)

    assert_not PositionManagement.save(@position)
    assert @position.errors[:require_training_for_roles].any?
  end

  test "save rejects no-training-required together with a training position" do
    @position.assign_attributes(no_training_required: true,
                                training_position_id: positions(:training_lead).id)

    assert_not PositionManagement.save(@position)
    assert @position.errors[:no_training_required].any?
  end

  test "save rejects a position that is its own parent" do
    @position.parent_position_id = @position.id

    assert_not PositionManagement.save(@position)
    assert @position.errors[:parent_position_id].any?
  end

  # Validated by the Ember form alone upstream, so the API accepted both.
  test "save rejects a negative sign out hour cap" do
    @position.sign_out_hour_cap = -1

    assert_not PositionManagement.save(@position)
    assert @position.errors[:sign_out_hour_cap].any?
  end

  test "save rejects a malformed contact email" do
    @position.contact_email = "not-an-address"

    assert_not PositionManagement.save(@position)
    assert @position.errors[:contact_email].any?
  end

  # Upstream's saving() hook: the automation columns are meaningless without
  # eligibility, and leaving them set would fire against an ineligible position.
  test "save zeroes the awards automation columns when awards eligibility is off" do
    position = positions(:mentor_lead)
    assert position.awards_auto_grant, "fixture must start with the automation on"

    position.awards_eligible = false

    assert PositionManagement.save(position)
    assert_not position.reload.awards_auto_grant
    assert_not position.awards_grants_service_year
  end

  test "save stores a blank paycode as NULL" do
    @position.paycode = ""

    assert PositionManagement.save(@position)
    assert_nil @position.reload.paycode
  end

  # ------------------------------------------------------- permission grants

  test "save syncs permission grants for a tech ninja" do
    assert PositionManagement.save(@position, role_ids: [Role::MENTOR], is_tech_ninja: true)
    assert_equal [Role::MENTOR], PositionRole.where(position_id: @position.id).pluck(:role_id)

    assert PositionManagement.save(@position, role_ids: [], is_tech_ninja: true)
    assert_empty PositionRole.where(position_id: @position.id)
  end

  test "save ignores submitted grants when the actor is not a tech ninja" do
    PositionManagement.save(@position, role_ids: [Role::MENTOR], is_tech_ninja: false)

    assert_empty PositionRole.where(position_id: @position.id)
  end

  test "save refuses to grant a role the actor does not hold" do
    assert_not PositionManagement.save(@position, role_ids: [Role::TECH_NINJA], is_tech_ninja: true)
    assert @position.errors[:role_ids].any?
  end

  test "save rejects a role id naming no role" do
    assert_not PositionManagement.save(@position, role_ids: [999_999], is_tech_ninja: true)
    assert @position.errors[:role_ids].any?
  end

  # ---------------------------------------------------------------- destroy

  # :position_lineups used to resolve to a position_lineup.position_id column
  # that does not exist, so reading it raised for EVERY position and took
  # position.destroy with it. It now goes through the join table.
  test "the lineup association reads without raising" do
    lineup = PositionLineup.create!(description: "Probe lineup")
    PositionLineupMember.create!(position_lineup_id: lineup.id, position_id: @position.id)

    assert_equal [lineup.id], @position.position_lineups.map(&:id)
  end

  # Deleting one member of a lineup must not take the lineup -- and its other
  # members -- with it.
  test "destroying a position leaves its lineup standing" do
    position = create_position
    lineup = PositionLineup.create!(description: "Probe lineup")
    PositionLineupMember.create!(position_lineup_id: lineup.id, position_id: position.id)

    assert PositionManagement.destroy(position)

    assert PositionLineup.exists?(lineup.id), "the lineup outlives its member"
    assert_empty PositionLineupMember.where(position_id: position.id)
  end

  # Position ids sit inside JSON lists there, out of a foreign key's reach, so
  # deleting a position has to go through them itself.
  test "destroy strips the position from the shift coverage definitions that read it" do
    position = create_position
    group = ShiftCoverageGroup.create!(slug: "probe", title: "Probe", sort_index: 99,
                                       base_position_ids: [position.id, @position.id])
    shared = ShiftCoveragePosition.create!(shift_coverage_group: group, title: "Shared", sort_index: 1,
                                           position_ids: [[position.id, "Mentee"], [@position.id]])
    only = ShiftCoveragePosition.create!(shift_coverage_group: group, title: "Only", sort_index: 2,
                                         position_ids: [[position.id]])
    bystander = shift_coverage_position(:command_ood)
    ActionLog.delete_all

    assert PositionManagement.destroy(position)

    assert_equal [@position.id], group.reload.base_position_ids
    assert_equal [[@position.id]], shared.reload.position_ids
    assert_equal [], only.reload.position_ids, "the post stays, reading nothing, until an admin chooses a position"
    assert_equal [[10]], bystander.reload.position_ids
    logged = ActionLog.where(ActionLog.arel_table[:event].matches("shift-coverage-%"))
    assert_equal({ "shift-coverage-group-update" => 1, "shift-coverage-position-update" => 2 },
                 logged.group(:event).count)
    assert_equal [PositionManagement::DELETE_REASON], logged.distinct.pluck(:message)
  end

  test "destroy removes the position and writes an audit entry" do
    position = create_position

    assert_difference "ActionLog.where(event: 'position-delete').count", 1 do
      assert PositionManagement.destroy(position)
    end

    assert_not Position.exists?(position.id)
  end

  # The user's ruling: shifts and their sign-ups go with the position.
  test "destroy deletes the position's shifts and their sign-ups" do
    position = create_position
    slot = create_slot(position)
    PersonSlot.create!(person_id: @admin.id, slot_id: slot.id)

    PositionManagement.destroy(position)

    assert_not Slot.exists?(slot.id), "the shift must go with the position"
    assert_empty PersonSlot.where(slot_id: slot.id), "the sign-ups must go with the shift"
  end

  test "destroy removes grants, awards, permission grants, and lineup membership" do
    # awards_eligible: PersonAward refuses to attach to a position that cannot
    # issue awards, so the position has to be able to before one can be granted.
    position = create_position(awards_eligible: true)
    PersonPosition.create!(person_id: @admin.id, position_id: position.id)
    PersonAward.create!(person_id: @admin.id, position_id: position.id, year: 2024, notes: "")
    PositionRole.create!(position_id: position.id, role_id: Role::MENTOR)
    lineup = PositionLineup.create!(description: "Test Lineup")
    PositionLineupMember.create!(position_lineup_id: lineup.id, position_id: position.id)

    PositionManagement.destroy(position)

    assert_empty PersonPosition.where(position_id: position.id)
    assert_empty PersonAward.where(position_id: position.id)
    assert_empty PositionRole.where(position_id: position.id)
    assert_empty PositionLineupMember.where(position_id: position.id)
    assert PositionLineup.exists?(lineup.id), "the lineup itself must survive losing a member"
  end

  # Upstream NULLs the children's parent_position_id but leaves
  # training_position_id dangling, naming a position that no longer exists.
  test "destroy releases child and trained positions rather than deleting them" do
    position = create_position
    child = create_position(title: "ZZ Child", parent_position_id: position.id)
    trained = create_position(title: "ZZ Trained", training_position_id: position.id)

    PositionManagement.destroy(position)

    assert Position.exists?(child.id)
    assert_nil child.reload.parent_position_id
    assert Position.exists?(trained.id)
    assert_nil trained.reload.training_position_id
  end

  # RoleManager reads require_training_for_roles together with
  # training_position_id. Leaving the flag set with the id NULLed means the
  # position confers nothing, with no training left that anyone could pass.
  test "destroy drops the training requirement it can no longer satisfy" do
    position = create_position
    trained = create_position(title: "ZZ Trained", training_position_id: position.id,
                              require_training_for_roles: true)

    PositionManagement.destroy(position)

    trained.reload

    assert_nil trained.training_position_id
    assert_not trained.require_training_for_roles,
               "a training requirement with nothing to pass withholds the roles from everyone"
    assert trained.valid?, "the released position must still be saveable"
  end

  test "destroy erases the training records hanging off its shifts" do
    position = create_position
    slot = create_slot(position)
    other_slot = create_slot(create_position(title: "ZZ Other"))
    TraineeStatus.create!(person_id: @admin.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)
    # trainer_slot_id elsewhere: Slot only cascades trainer_status through that
    # column, so this row is the one the cascade used to leave behind.
    TrainerStatus.create!(person_id: @admin.id, slot_id: slot.id, trainer_slot_id: other_slot.id)

    PositionManagement.destroy(position)

    assert_empty TraineeStatus.where(slot_id: slot.id)
    assert_empty TrainerStatus.where(slot_id: slot.id)
  end

  test "destroy clears the rows that carry a NOT NULL position_id" do
    position = create_position
    PositionCredit.create!(position_id: position.id, start_time: Time.current,
                           end_time: Time.current + 1.hour, credits_per_hour: 1.0,
                           description: "Probe")

    PositionManagement.destroy(position)

    assert_empty PositionCredit.where(position_id: position.id),
                 "an orphan here is unreachable from every page and unremovable"
  end

  # Service hours are the organisation's record of who rangered what. There is
  # nothing to release -- timesheet.position_id is NOT NULL -- so the delete is
  # refused rather than allowed to erase them or leave orphans behind.
  test "destroy refuses a position that carries service history" do
    position = create_position
    Timesheet.create!(person_id: @admin.id, position_id: position.id,
                      on_duty: Time.current - 2.hours, additional_notes: "Probe entry")

    assert_not PositionManagement.destroy(position)
    assert position.errors[:base].any?
    assert Position.exists?(position.id), "the position must survive the refusal"
  end

  test "child counts name the service history that blocks a delete" do
    position = create_position
    Timesheet.create!(person_id: @admin.id, position_id: position.id,
                      on_duty: Time.current - 2.hours, additional_notes: "Probe entry")

    assert_equal 1, PositionManagement.child_counts(position)[:timesheet_count]
  end

  # The audit trail of who held the position and when. Upstream keeps it too.
  test "destroy keeps the position's grant history log" do
    position = create_position
    PersonPositionLog.create!(person_id: @admin.id, position_id: position.id, joined_on: Date.current)

    PositionManagement.destroy(position)

    assert_equal 1, PersonPositionLog.where(position_id: position.id).count
  end

  test "child counts name every child a delete would take" do
    position = create_position
    slot = create_slot(position)
    PersonSlot.create!(person_id: @admin.id, slot_id: slot.id)
    PersonPosition.create!(person_id: @admin.id, position_id: position.id)

    counts = PositionManagement.child_counts(position)

    assert_equal 1, counts[:slot_count]
    assert_equal 1, counts[:signup_count]
    assert_equal 1, counts[:grant_count]
  end

  test "child counts name the Shift Coverage lists a delete takes the position out of" do
    position = create_position
    shift_coverage_group(:command).update_columns(base_position_ids: [position.id])
    shift_coverage_position(:command_ts).update_columns(position_ids: [[position.id, "Mentee"]])

    counts = PositionManagement.child_counts(position)

    assert_equal 1, counts[:shift_coverage_type_count]
    assert_equal 1, counts[:shift_coverage_post_count]
  end

  test "child counts read zero for a position that does not exist yet" do
    counts = PositionManagement.child_counts(Position.new)

    assert_equal 0, counts[:slot_count]
    assert_equal 0, counts[:grant_count]
  end

  private

  def create_position(title: "ZZ Doomed Position", **attributes)
    Position.create!(title:, type: Position::TYPE_OTHER, **attributes)
  end

  def create_slot(position)
    begins = Time.zone.parse("2024-08-25 12:00:00")
    Slot.create!(position_id: position.id, begins:, ends: begins + 4.hours,
                 description: "Test shift", max: 5, active: true,
                 timezone: "America/Los_Angeles", timezone_abbr: "PDT")
  end
end
