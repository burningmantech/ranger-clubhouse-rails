# frozen_string_literal: true

require "test_helper"

# The person page's permission rows: what RoleManager has in effect, and every
# path by which the person holds each permission, met or not.
class PersonPermissionPresenterTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper
  include TrainingSlotTestHelper
  include PersonTestFactory

  setup do
    # An entry signed in an hour ago must fall in this year, which it does not
    # just after New Year.
    travel_to Time.zone.local(Current.year, 8, 28, 12)
    Current.reset
    # Creating the NDA document writes an audit row, which needs someone acting.
    Current.person = person(:auditor_ranger)
    ensure_role(Role::VIEW_EMAIL, "View Email")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EVENT_MANAGEMENT_ON_PLAYA, "Event Management On Playa")

    @person = create_person("Pathfinder")
    @training = Position.create!(id: Position::TRAINING, title: "In-Person Training",
                                 type: Position::TYPE_TRAINING, active: true)
    @position = Position.create!(title: "Gated Position", type: Position::TYPE_FRONTLINE, active: true,
                                 require_training_for_roles: true, training_position_id: @training.id,
                                 require_signin_for_roles: true)
    PositionRole.create!(position_id: @position.id, role_id: Role::VIEW_EMAIL)
    PersonPosition.create!(person_id: @person.id, position_id: @position.id)
    set_on_playa(false)
  end

  teardown { Current.reset }

  test "a permission held only through a gated position shows the unmet conditions" do
    row = row_for(Role::VIEW_EMAIL)

    assert_not row.active
    path = row.paths.sole
    assert_equal :position, path.kind
    assert_equal "Gated Position", path.title
    assert_equal [false, false], path.conditions.map(&:met)
    assert_equal ["Has not passed or taught In-Person Training in #{Current.year}", "Not signed in to Gated Position"],
                 path.conditions.map(&:text)
    assert_not path.confers?
    assert_not_includes RoleManager.retrieve(@person).granted_roles, Role::VIEW_EMAIL,
                        "RoleManager leaves it out, which is why the old section never showed it"
  end

  test "training passed and signed in makes the position path confer and the row active" do
    pass_training
    go_on_duty(@position)

    row = row_for(Role::VIEW_EMAIL)

    assert row.active
    # Training.did_person_pass_for_year? counts teaching the training too.
    assert_equal ["Passed or taught In-Person Training in #{Current.year}", "Signed in to Gated Position"],
                 row.paths.sole.conditions.map(&:text)
    assert row.paths.sole.confers?
  end

  test "trained but signed in to a different position leaves the sign-in condition unmet" do
    pass_training
    go_on_duty(Position.create!(title: "Other Position", type: Position::TYPE_FRONTLINE, active: true))

    row = row_for(Role::VIEW_EMAIL)

    assert_not row.active
    assert_equal [true, false], row.paths.sole.conditions.map(&:met)
    # RoleManager counts only the newest open entry, so name the one it counted.
    assert_equal "Signed in to Other Position, not Gated Position", row.paths.sole.conditions.last.text
  end

  test "an older open entry for the position is named, with the newer one that counts" do
    pass_training
    go_on_duty(@position)
    travel 30.minutes
    go_on_duty(Position.create!(title: "Other Position", type: Position::TYPE_FRONTLINE, active: true))

    row = row_for(Role::VIEW_EMAIL)

    assert_not row.active
    assert_equal "Signed in to Gated Position, but the newer sign-in to Other Position is the one that counts",
                 row.paths.sole.conditions.last.text
  end

  test "a training position that no longer exists is one nobody can pass" do
    pass_training
    @position.update_columns(training_position_id: 987_654, require_signin_for_roles: false)

    row = row_for(Role::VIEW_EMAIL)

    assert_not row.active
    condition = row.paths.sole.conditions.sole
    assert_not condition.met
    assert_equal "Requires training, but its training position (#987654) no longer exists", condition.text
  end

  test "a position that requires training but names none shows the condition unmet" do
    @position.update_columns(training_position_id: nil, require_signin_for_roles: false)

    row = row_for(Role::VIEW_EMAIL)

    assert_not row.active
    assert_equal "Requires training, but no training position is set", row.paths.sole.conditions.sole.text
    assert_not row.paths.sole.confers?
  end

  # RoleManager reads only active positions, so an inactive one is no path.
  test "an inactive position is no path, even with its conditions met, until it is reactivated" do
    pass_training
    go_on_duty(@position)
    @position.update_columns(active: false)

    assert_nil row_for(Role::VIEW_EMAIL)

    @position.update_columns(active: true)
    assert row_for(Role::VIEW_EMAIL).paths.sole.confers?
  end

  test "the editor lists no inactive position as granting a permission until it is reactivated" do
    @position.update_columns(active: false)
    assert_empty role_item(Role::VIEW_EMAIL).position_titles

    @position.update_columns(active: true)
    assert_equal ["Gated Position"], role_item(Role::VIEW_EMAIL).position_titles
  end

  test "a team grant keeps the row active while the position path still shows its unmet conditions" do
    team = Team.create!(title: "Test Cadre", active: true)
    TeamRole.create!(team_id: team.id, role_id: Role::VIEW_EMAIL)
    PersonTeam.create!(person_id: @person.id, team_id: team.id)

    row = row_for(Role::VIEW_EMAIL)

    assert row.active
    assert_equal [:team, :position], row.paths.map(&:kind)
    assert_equal "Test Cadre", row.paths.first.title
    assert_not row.paths.last.confers?
  end

  test "paths list manual grants first, then teams, then positions" do
    grant_role(@person, Role::VIEW_EMAIL)
    team = Team.create!(title: "Test Cadre", active: true)
    TeamRole.create!(team_id: team.id, role_id: Role::VIEW_EMAIL)
    PersonTeam.create!(person_id: @person.id, team_id: team.id)

    assert_equal [:manual, :team, :position], row_for(Role::VIEW_EMAIL).paths.map(&:kind)
  end

  test "rows are ordered by permission title" do
    grant_role(@person, Role::MENTOR)

    assert_equal ["Mentor", "View Email"], rows.map(&:title)
  end

  test "a permission nobody grants this person has no row" do
    assert_nil rows.find { |row| row.title == "Event Management" }
  end

  test "off-season Event Management On Playa is inactive and names the setting" do
    grant_role(@person, Role::EVENT_MANAGEMENT_ON_PLAYA)

    row = row_for(Role::EVENT_MANAGEMENT_ON_PLAYA)

    assert_not row.active
    assert_equal Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED, row.off_setting
    assert_nil row_for(Role::EVENT_MANAGEMENT), "nothing is conferred while the setting is off"
  end

  test "while the setting is on Event Management On Playa brings Event Management, listed as conferred" do
    grant_role(@person, Role::EVENT_MANAGEMENT_ON_PLAYA)
    set_on_playa(true)

    on_playa = row_for(Role::EVENT_MANAGEMENT_ON_PLAYA)
    management = row_for(Role::EVENT_MANAGEMENT)

    assert on_playa.active
    assert_nil on_playa.off_setting
    assert management.active
    path = management.paths.sole
    assert_equal :conferred, path.kind
    assert_equal "Event Management On Playa", path.title
    assert_equal Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED, path.setting
  end

  test "a source that does not confer brings nothing even while the setting is on" do
    # Event Management On Playa only through a gated position the person has not met.
    PositionRole.create!(position_id: @position.id, role_id: Role::EVENT_MANAGEMENT_ON_PLAYA)
    set_on_playa(true)

    assert_nil row_for(Role::EVENT_MANAGEMENT)
    assert_not row_for(Role::EVENT_MANAGEMENT_ON_PLAYA).active
  end

  test "a setting holding a permission off is named even beside unmet conditions" do
    PositionRole.create!(position_id: @position.id, role_id: Role::EVENT_MANAGEMENT_ON_PLAYA)

    row = row_for(Role::EVENT_MANAGEMENT_ON_PLAYA)

    assert_not row.active
    assert_not row.paths.sole.confers?
    assert_equal Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED, row.off_setting, "meeting the conditions would not turn it on"
  end

  test "an unsigned NDA still names the setting that keeps a permission off after signing" do
    grant_role(@person, Role::EVENT_MANAGEMENT)
    grant_role(@person, Role::EVENT_MANAGEMENT_ON_PLAYA)
    create_nda

    role_manager = RoleManager.retrieve(@person)
    result = PersonPermissionPresenter.new(person: @person).overview_rows(role_manager)

    assert role_manager.nda_blocked?
    assert result.none?(&:active)
    assert_nil result.find { |row| row.title == "Event Management" }.off_setting
    assert_equal Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED,
                 result.find { |row| row.title == "Event Management On Playa" }.off_setting
  end

  # Status comes from RoleManager's cached set, so the rows must not lose or
  # invent a permission when fresh paths disagree with it.
  test "a permission RoleManager has in effect gets a row even with no current grant" do
    row = overview(cached_role_manager(roles: [Role::MENTOR], granted: [Role::MENTOR])).find { |r| r.title == "Mentor" }

    assert row, "a permission in effect went unlisted"
    assert row.active
    assert_empty row.paths
  end

  test "a conferred row follows RoleManager's grants, not a fresh reading of the paths" do
    set_on_playa(true)
    grant_role(@person, Role::EVENT_MANAGEMENT_ON_PLAYA)

    stale = overview(cached_role_manager(roles: [], granted: []))
    assert_nil stale.find { |row| row.title == "Event Management" }, "RoleManager conferred nothing"

    granted = overview(cached_role_manager(roles: [Role::EVENT_MANAGEMENT_ON_PLAYA, Role::EVENT_MANAGEMENT],
                                           granted: [Role::EVENT_MANAGEMENT_ON_PLAYA]))
    assert_equal :conferred, granted.find { |row| row.title == "Event Management" }.paths.sole.kind
  end

  test "an unsigned NDA turns every row inactive and names no setting for ungated ones" do
    grant_role(@person, Role::EVENT_MANAGEMENT)
    grant_role(@person, Role::MENTOR)
    create_nda

    role_manager = RoleManager.retrieve(@person)
    result = PersonPermissionPresenter.new(person: @person).overview_rows(role_manager)

    assert role_manager.nda_blocked?
    assert_equal ["Event Management", "Mentor", "View Email"], result.map(&:title)
    assert result.none?(&:active)
    assert result.all? { |row| row.off_setting.nil? }
  end

  private

  def rows
    PersonPermissionPresenter.new(person: @person).overview_rows(RoleManager.retrieve(@person))
  end

  def row_for(role_id)
    title = Role.find(role_id).title
    rows.find { |row| row.title == title }
  end

  def role_item(role_id)
    PersonPermissionPresenter.new(person: @person).role_items.find { |item| item.id == role_id }
  end

  def overview(role_manager)
    PersonPermissionPresenter.new(person: @person).overview_rows(role_manager)
  end

  # A role set as RoleManager would read it back from the cache.
  def cached_role_manager(roles:, granted:)
    RoleManager.new.tap do |role_manager|
      role_manager.roles = roles
      role_manager.granted_roles = granted
      role_manager.directly_assign_roles = []
      role_manager.roles_loaded = true
    end
  end

  def go_on_duty(position)
    Timesheet.create!(person_id: @person.id, position_id: position.id, on_duty: Current.time - 1.hour,
                      additional_notes: "signed in")
  end

  # person_create_id / person_update_id are NOT NULL in the schema.
  def create_nda
    Document.create!(tag: Document::DEPT_NDA_TAG, description: "Department NDA", body: "body",
                     person_create_id: Current.person.id, person_update_id: Current.person.id)
  end

  def pass_training
    slot = create_slot(@training, begins: Time.zone.local(Current.year, 6, 14, 9))
    TraineeStatus.create!(person_id: @person.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)
  end

  def set_on_playa(enabled)
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: enabled.to_s)
  end
end
