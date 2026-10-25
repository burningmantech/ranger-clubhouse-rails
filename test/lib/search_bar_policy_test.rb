# frozen_string_literal: true

require "test_helper"

class SearchBarPolicyTest < ActiveSupport::TestCase
  def stub_roles(role_ids)
    rm = RoleManager.new
    rm.roles = Array(role_ids)
    Current.roles_manager = rm
  end

  teardown do
    Current.reset
  end

  test "returns false with no person argument" do
    stub_roles([Role::ADMIN])
    assert_not SearchBarPolicy.allowed?
  end

  test "returns false with nil person argument" do
    stub_roles([Role::ADMIN])
    assert_not SearchBarPolicy.allowed?(nil)
  end

  test "returns false for a person with no enabling roles" do
    stub_roles([])
    assert_not SearchBarPolicy.allowed?(person(:active_ranger))
  end

  test "returns true for event management and event management on playa" do
    [Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA].each do |role_id|
      stub_roles([role_id])
      assert SearchBarPolicy.allowed?(person(:active_ranger)),
             "role #{role_id} should enable the search bar"
    end
  end

  test "returns false without event management, even for an admin" do
    stub_roles([Role::ADMIN, Role::SHIFT_MANAGEMENT, Role::VIEW_PII])
    assert_not SearchBarPolicy.allowed?(person(:active_ranger))
  end

  # ---------------------------------------------------------------------------
  # Mode switcher descriptors + gated hq mode
  # (The HQWindowInterfaceEnabled setting defaults to on; tests disable it
  # explicitly to exercise the off state.)
  # ---------------------------------------------------------------------------

  test "mode_options is person_manage only without the HQ window roles" do
    stub_roles([Role::VIEW_PII])

    options = SearchBarPolicy.mode_options
    assert_equal %w[person_manage], options.map { |o| o[:value] },
                 "hq must be withheld from viewers without Admin/Shift Management"

    person_manage = options.first
    assert_equal "Person Manage", person_manage[:label]
    assert person_manage[:enabled], "person_manage is always enabled"
  end

  test "mode_options adds an enabled HQ Window mode for shift management" do
    stub_roles([Role::SHIFT_MANAGEMENT])

    options = SearchBarPolicy.mode_options
    assert_equal %w[person_manage hq], options.map { |o| o[:value] },
                 "person_manage must precede hq"

    hq = options.last
    assert_equal "HQ Window", hq[:label]
    assert hq[:enabled], "hq must be a real, selectable mode when available"
  end

  test "mode_options adds the hq mode for admins" do
    stub_roles([Role::ADMIN])
    assert_includes SearchBarPolicy.mode_options.map { |o| o[:value] }, "hq"
  end

  test "hq mode is withheld when the HQ Window Interface setting is off" do
    disable_hq_window_interface
    stub_roles([Role::SHIFT_MANAGEMENT])

    assert_not SearchBarPolicy.hq_mode_available?
    assert_equal %w[person_manage], SearchBarPolicy.mode_options.map { |o| o[:value] }
  end

  test "enabled_modes tracks hq availability" do
    stub_roles([])
    assert_equal ["person_manage"], SearchBarPolicy.enabled_modes

    stub_roles([Role::SHIFT_MANAGEMENT])
    assert_equal %w[person_manage hq], SearchBarPolicy.enabled_modes
  end

  # ---------------------------------------------------------------------------
  # Permission-gated Timesheet / Swag modes
  # ---------------------------------------------------------------------------

  test "mode_options adds the Timesheet mode for timesheet management" do
    stub_roles([Role::TIMESHEET_MANAGEMENT])

    options = SearchBarPolicy.mode_options
    assert_equal %w[person_manage timesheet], options.map { |o| o[:value] }
    assert_equal "Timesheet", options.last[:label]
  end

  test "mode_options adds the Swag mode for the quartermaster" do
    stub_roles([Role::QUARTERMASTER])

    options = SearchBarPolicy.mode_options
    assert_equal %w[person_manage swag], options.map { |o| o[:value] }
    assert_equal "Swag", options.last[:label]
  end

  test "mode_options withholds Timesheet and Swag from a viewer holding neither" do
    stub_roles([Role::VIEW_PII])

    values = SearchBarPolicy.mode_options.map { |o| o[:value] }
    assert_not_includes values, "timesheet"
    assert_not_includes values, "swag"
  end

  test "an admin gets every mode" do
    stub_roles([Role::ADMIN])

    assert_equal %w[person_manage hq timesheet swag], SearchBarPolicy.enabled_modes
  end

  test "path_template_for only answers for modes the viewer holds" do
    stub_roles([Role::QUARTERMASTER])

    assert_equal "/person/:id/swag", SearchBarPolicy.path_template_for("swag")
    assert_nil SearchBarPolicy.path_template_for("timesheet"),
               "a mode the viewer cannot use must have no destination"
    assert_nil SearchBarPolicy.path_template_for("nonsense")
  end

  test "MODE_PATHS match the routes they name" do
    id = 42
    expected = {
      "person_manage" => Rails.application.routes.url_helpers.person_path(id),
      "hq" => Rails.application.routes.url_helpers.hq_path(id),
      "timesheet" => Rails.application.routes.url_helpers.person_timesheets_path(id),
      "swag" => Rails.application.routes.url_helpers.person_swag_index_path(id)
    }
    actual = SearchBarPolicy::MODE_PATHS.transform_values { |t| t.sub(":id", id.to_s) }

    assert_equal expected, actual
  end

  # ---------------------------------------------------------------------------
  # Onduty-driven default mode: auto-select hq when the viewer's on-duty
  # position subtype is HQ or mentor (Ember search-item-bar parity).
  # ---------------------------------------------------------------------------

  test "default_mode is person_manage when the viewer is not on duty" do
    stub_roles([Role::SHIFT_MANAGEMENT])
    Current.person = person(:active_ranger)

    assert_equal SearchBarPolicy::MODE_PERSON_MANAGE, SearchBarPolicy.default_mode
  end

  test "default_mode auto-selects hq when on duty in an HQ Window position" do
    stub_roles([Role::SHIFT_MANAGEMENT])
    sign_on_duty(person(:active_ranger), type: Position::TYPE_HQ)

    assert_equal SearchBarPolicy::MODE_HQ, SearchBarPolicy.default_mode
  end

  test "default_mode auto-selects hq when on duty in a mentor position" do
    stub_roles([Role::SHIFT_MANAGEMENT])
    sign_on_duty(person(:active_ranger), type: Position::TYPE_MENTORING)

    assert_equal SearchBarPolicy::MODE_HQ, SearchBarPolicy.default_mode
  end

  test "default_mode stays person_manage for a non-hq on-duty position" do
    stub_roles([Role::SHIFT_MANAGEMENT])
    sign_on_duty(person(:active_ranger), type: Position::TYPE_FRONTLINE)

    assert_equal SearchBarPolicy::MODE_PERSON_MANAGE, SearchBarPolicy.default_mode
  end

  test "default_mode stays person_manage for an on-duty mentee position" do
    stub_roles([Role::SHIFT_MANAGEMENT])
    # The Alpha position id makes Position#subtype report "mentee", not "mentor".
    sign_on_duty(person(:active_ranger), type: Position::TYPE_MENTORING, position_id: Position::ALPHA)

    assert_equal SearchBarPolicy::MODE_PERSON_MANAGE, SearchBarPolicy.default_mode
  end

  test "default_mode ignores the on-duty context when the hq mode is unavailable" do
    disable_hq_window_interface
    stub_roles([Role::SHIFT_MANAGEMENT])
    sign_on_duty(person(:active_ranger), type: Position::TYPE_HQ)

    assert_equal SearchBarPolicy::MODE_PERSON_MANAGE, SearchBarPolicy.default_mode
  end

  private

  # Put a person on duty right now in a freshly-created position of the given
  # type, and make them the viewer. Mirrors the open-entry setup pinned by
  # test/models/current_test.rb (Current.onduty_entry).
  def sign_on_duty(person, type:, position_id: nil)
    position = Position.new(title: "#{type} Duty", active: true, no_training_required: true, type: type)
    position.id = position_id if position_id
    position.save!

    entry = Timesheet.new(person_id: person.id, position_id: position.id, on_duty: Current.time - 2.hours)
    entry.save!(validate: false)

    Current.person = person
  end

  def disable_hq_window_interface
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")
  end
end
