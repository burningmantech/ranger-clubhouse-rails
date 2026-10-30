# frozen_string_literal: true

require "test_helper"

# The rules RoleManager lays over the granted roles that turn on the season and
# on the Department NDA.
class RoleManagerTest < ActiveSupport::TestCase
  include CacheTestHelper
  include TimesheetAdminTestHelper
  include TrainingSlotTestHelper

  setup do
    Current.reset
    # Creating the NDA document writes an audit row, which needs someone acting.
    Current.person = person(:auditor_ranger)
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EVENT_MANAGEMENT_ON_PLAYA, "Event Management On Playa")

    @person = person(:active_ranger)
    PersonEvent.where(person_id: @person.id).delete_all
    grant_role(@person, Role::MENTOR)
    set_on_playa(false)
  end

  teardown do
    # Current.reset leaves plain accessors alone.
    Current.groundhog_day_time = nil
    Current.reset
  end

  test "off-season the raw on-playa role is dropped and the other roles kept" do
    grant_role(@person, Role::EVENT_MANAGEMENT_ON_PLAYA)

    roles = RoleManager.retrieve(@person)

    assert_not roles.has_role?([Role::EVENT_MANAGEMENT_ON_PLAYA, Role::EVENT_MANAGEMENT])
    assert roles.has_role?(Role::MENTOR)
    assert_includes roles.granted_roles, Role::EVENT_MANAGEMENT_ON_PLAYA
  end

  test "an on-playa holder who has not signed the NDA loses every role while the setting is on" do
    grant_role(@person, Role::EVENT_MANAGEMENT_ON_PLAYA)
    set_on_playa(true)
    create_nda

    roles = RoleManager.retrieve(@person)

    assert_empty roles.roles
    assert roles.nda_blocked?
  end

  # GroundHogDay.train_actives hands every active Ranger the on-playa role and
  # turns the setting on, and a training copy has no NDA signatures at all.
  test "the NDA takes nothing away on the Groundhog Day server" do
    grant_role(@person, Role::EVENT_MANAGEMENT_ON_PLAYA)
    set_on_playa(true)
    create_nda
    Current.groundhog_day_time = Time.zone.local(2025, 8, 28, 12)

    roles = RoleManager.retrieve(@person)

    assert roles.has_role?(Role::EVENT_MANAGEMENT)
    assert roles.has_role?(Role::MENTOR)
  end

  test "an Event Manager the NDA wiped is asked to sign it, and signing gives the roles back" do
    grant_role(@person, Role::EVENT_MANAGEMENT)
    create_nda
    Current.person = @person
    Current.roles_manager = RoleManager.retrieve(@person)

    assert_not @person.has_role?(Role::EVENT_MANAGEMENT)
    assert Milestones.build_for_person(@person).nda_required, "the dashboard did not ask for the NDA"

    Agreements.sign_agreement(@person, Document::DEPT_NDA_TAG)

    roles = RoleManager.retrieve(@person)

    assert roles.has_role?(Role::EVENT_MANAGEMENT)
    assert_not roles.nda_blocked?
  end

  # has_raw_role? answers from the roles the wipe took, which only a freshly
  # built set carries, so a wiped set must never reach the cache.
  test "a wiped role set is never cached" do
    grant_role(@person, Role::EVENT_MANAGEMENT)
    create_nda

    with_cache_store do |cache|
      assert RoleManager.retrieve(@person).has_raw_role?(Role::EVENT_MANAGEMENT)
      assert_not cache.exist?(RoleManager.cache_key(@person.id))
    end
  end

  test "Training Interface Seasonal brings Training Interface Year Round only while its setting is on" do
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::TRAINER_SEASONAL, "Trainer Seasonal")
    grant_role(@person, Role::TRAINER_SEASONAL)

    set_setting(Setting::TRAINING_SEASONAL_ROLE_ENABLED, false)
    assert_not RoleManager.retrieve(@person).has_role?(Role::TRAINER)

    set_setting(Setting::TRAINING_SEASONAL_ROLE_ENABLED, true)
    roles = RoleManager.retrieve(@person)
    assert roles.has_role?(Role::TRAINER)
    assert roles.has_role?(Role::TRAINER_SEASONAL)
    assert_not_includes roles.granted_roles, Role::TRAINER, "a conferred permission is not a grant"
  end

  test "Shift Management Self is dropped while its setting is off" do
    ensure_role(Role::SHIFT_MANAGEMENT_SELF, "Shift Management Self")
    grant_role(@person, Role::SHIFT_MANAGEMENT_SELF)

    set_setting(Setting::SHIFT_MANAGEMENT_SELF_ENABLED, false)
    roles = RoleManager.retrieve(@person)
    assert_not roles.has_role?(Role::SHIFT_MANAGEMENT_SELF)
    assert_includes roles.granted_roles, Role::SHIFT_MANAGEMENT_SELF

    set_setting(Setting::SHIFT_MANAGEMENT_SELF_ENABLED, true)
    assert RoleManager.retrieve(@person).has_role?(Role::SHIFT_MANAGEMENT_SELF)
  end

  test "a position that requires training and sign-in confers its permission only to someone trained and signed in" do
    pin_clock_mid_year
    training, position = gated_position

    assert_not RoleManager.retrieve(@person).has_role?(Role::VIEW_EMAIL), "untrained and off duty"

    slot = create_slot(training, begins: Time.zone.local(Current.year, 6, 14, 9))
    TraineeStatus.create!(person_id: @person.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)
    roles = RoleManager.retrieve(@person)
    assert_not roles.has_role?(Role::VIEW_EMAIL), "trained but off duty"
    assert_not_includes roles.granted_roles, Role::VIEW_EMAIL

    go_on_duty(position)
    assert RoleManager.retrieve(@person).has_role?(Role::VIEW_EMAIL), "trained and on duty"
  end

  test "a signed-in but untrained holder gets nothing from a training-gated position" do
    pin_clock_mid_year
    _, position = gated_position
    go_on_duty(position)

    assert_not RoleManager.retrieve(@person).has_role?(Role::VIEW_EMAIL)
  end

  # Clubhouse 2 skipped such a position; the port used to confer it to everyone.
  test "a position that requires training but names no training position confers nothing" do
    _, position = gated_position
    # Validation refuses this state, but destroying a training position leaves it behind.
    position.update_columns(training_position_id: nil, require_signin_for_roles: false)

    assert_not RoleManager.retrieve(@person).has_role?(Role::VIEW_EMAIL)
  end

  test "a position that requires only sign-in confers its permission only while signed in to it" do
    pin_clock_mid_year
    position = held_view_email_position(title: "Sign-In Position", require_signin_for_roles: true)
    other = Position.create!(title: "Other Position", type: Position::TYPE_FRONTLINE, active: true)
    assert_not RoleManager.retrieve(@person).has_role?(Role::VIEW_EMAIL), "off duty"

    go_on_duty(other)
    assert_not RoleManager.retrieve(@person).has_role?(Role::VIEW_EMAIL), "on duty for a different position"

    Timesheet.where(person_id: @person.id).destroy_all
    go_on_duty(position)
    assert RoleManager.retrieve(@person).has_role?(Role::VIEW_EMAIL), "on duty for it"
  end

  # This year's NDA, training and sign-in decide the set, and nothing purges on
  # January 1, so the cache key carries the year.
  test "a role set cached in December does not answer for January" do
    grant_role(@person, Role::EVENT_MANAGEMENT)
    create_nda
    year = Current.year
    travel_to Time.zone.local(year, 12, 30, 12)
    event = PersonEvent.first_or_new_for_person_year(@person.id, year)
    event.signed_nda = true
    event.save!(validate: false)

    with_cache_store do |cache|
      assert RoleManager.retrieve(@person).has_role?(Role::EVENT_MANAGEMENT), "signed this year's NDA"
      assert cache.exist?(RoleManager.cache_key(@person.id, year)), "the December set was not cached; nothing to prove"

      travel_to Time.zone.local(year + 1, 1, 2, 12)
      assert RoleManager.retrieve(@person).nda_blocked?, "last year's signature answered for the new year"
    end
  end

  # A purge landing between an exist? and a read used to leave the roles nil,
  # and has_role? then raised. This store answers exist? yes and read nothing.
  test "a role set gone by the time it is read is rebuilt" do
    original = Rails.cache
    Rails.cache = Class.new(ActiveSupport::Cache::MemoryStore) { def exist?(*) = true }.new

    assert RoleManager.retrieve(@person).has_role?(Role::MENTOR)
  ensure
    Rails.cache = original
  end

  test "a position that gates on nothing confers its permission to everyone who holds it" do
    held_view_email_position(title: "Open Position")

    assert RoleManager.retrieve(@person).has_role?(Role::VIEW_EMAIL)
  end

  # Clubhouse 2 read only active positions; the port used to read them all.
  test "an inactive position confers nothing until it is reactivated" do
    position = held_view_email_position(title: "Retired Position", active: false)
    assert_not RoleManager.retrieve(@person).has_role?(Role::VIEW_EMAIL), "inactive"

    position.update_columns(active: true)
    assert RoleManager.retrieve(@person).has_role?(Role::VIEW_EMAIL), "reactivated"
  end

  private

  # An entry signed in an hour ago must fall in this year, which it does not
  # just after New Year.
  def pin_clock_mid_year
    travel_to Time.zone.local(Current.year, 8, 28, 12)
  end

  # A position granting View Email only to holders trained in In-Person
  # Training and signed in to it. Returns [training, position].
  def gated_position
    training = Position.create!(id: Position::TRAINING, title: "In-Person Training",
                                type: Position::TYPE_TRAINING, active: true)
    position = held_view_email_position(title: "Gated Position", require_training_for_roles: true,
                                        training_position_id: training.id, require_signin_for_roles: true)
    [training, position]
  end

  # A frontline position granting View Email, held by @person.
  def held_view_email_position(**attributes)
    ensure_role(Role::VIEW_EMAIL, "View Email")
    position = Position.create!(type: Position::TYPE_FRONTLINE, active: true, **attributes)
    PositionRole.create!(position_id: position.id, role_id: Role::VIEW_EMAIL)
    PersonPosition.create!(person_id: @person.id, position_id: position.id)
    position
  end

  def go_on_duty(position)
    Timesheet.create!(person_id: @person.id, position_id: position.id, on_duty: Current.time - 1.hour,
                      additional_notes: "signed in")
  end

  def set_setting(name, enabled)
    Setting.find_or_initialize_by(name:).update!(value: enabled.to_s)
  end

  def set_on_playa(enabled)
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: enabled.to_s)
  end

  # person_create_id / person_update_id are NOT NULL in the schema.
  def create_nda
    Document.create!(tag: Document::DEPT_NDA_TAG, description: "Department NDA", body: "body",
                     person_create_id: Current.person.id, person_update_id: Current.person.id)
  end
end
