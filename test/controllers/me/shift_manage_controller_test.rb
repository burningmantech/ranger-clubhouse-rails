# frozen_string_literal: true

require "test_helper"

class Me::ShiftManageControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @person = person(:active_ranger)

    # RoleManager only surfaces SHIFT_MANAGEMENT_SELF while the feature flag is on.
    Setting.find_or_create_by(name: Setting::SHIFT_MANAGEMENT_SELF_ENABLED).update!(value: "true")

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::SHIFT_MANAGEMENT_SELF, "Shift Management Self")
    ensure_role(Role::CAN_FORCE_SHIFT, "Force Shift Start")
    grant_role(@person, Role::SHIFT_MANAGEMENT_SELF)

    @position = Position.create!(title: "Sunrise Patrol", active: true, no_training_required: true)
    PersonPosition.create!(person_id: @person.id, position_id: @position.id)

    sign_in_as(@person)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "the page requires the shift management self permission" do
    sign_in_as(person(:ranger_with_custom_gender))

    get me_shift_manage_path

    assert_redirected_to me_root_path
  end

  test "off duty, the page offers the start shift picker" do
    get me_shift_manage_path

    assert_response :success
    assert_select "section", text: /Start a Shift/
    assert_select "option", text: "Sunrise Patrol"
  end

  test "on duty, the page shows the current shift with an end shift action" do
    start_shift!

    get me_shift_manage_path

    assert_response :success
    assert_select "#current-shift", text: /Sunrise Patrol/
    assert_select "a", text: /End Shift/
    assert_select "a", text: /Correct Position/
  end

  test "on duty, self-serve does not offer end shift with correction" do
    start_shift!

    get me_shift_manage_path

    assert_response :success
    # allow_correction_on_end? is false here: only the HQ Window's return path
    # carries ctx_correction, so the button would end the shift and silently
    # drop the correction.
    assert_select "a", text: /End Shift & Submit Correction/, count: 0
  end

  test "start shift checks the person in and logs the check-in" do
    post me_shift_manage_start_path, params: { position_id: @position.id }

    assert_redirected_to me_shift_manage_path
    entry = Timesheet.find_person_on_duty(@person.id)
    assert entry
    assert_equal @position.id, entry.position_id
    assert TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::SIGNON).exists?
  end

  test "a blocked start renders the blocker modal instead of checking in" do
    blocked = Position.create!(title: "Blocked Position", active: true, no_training_required: false)
    PersonPosition.create!(person_id: @person.id, position_id: blocked.id)

    post me_shift_manage_start_path, params: { position_id: blocked.id }

    assert_response :success
    assert_match "Check In Is Blocked", response.body
    assert_match "Refer the person to the HQ Lead", response.body
    assert_nil Timesheet.find_person_on_duty(@person.id)

    grant_role(@person, Role::CAN_FORCE_SHIFT)
    post me_shift_manage_start_path, params: { position_id: blocked.id }
    assert_match "All forced actions are logged", response.body

    post me_shift_manage_start_path,
         params: { position_id: blocked.id, force_sign_in: 1, signin_force_reason: "trainer confirmed" }
    assert_redirected_to me_shift_manage_path
    entry = Timesheet.find_person_on_duty(@person.id)
    assert entry.was_signin_forced
    assert_equal "trainer confirmed", entry.signin_force_reason
  end

  test "end shift signs the person off" do
    entry = start_shift!
    travel 6.hours

    post me_shift_manage_end_path, params: { entry_id: entry.id }

    assert_redirected_to me_shift_manage_path
    assert_equal Current.time, entry.reload.off_duty
    assert TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::SIGNOFF).exists?
  end

  # FlashHash#delete returns the flash, not the value: testing its presence
  # opened the modal whenever the redirect carried a toast.
  test "an already-active person sees no restored-to-active modal after starting or ending a shift" do
    post me_shift_manage_start_path, params: { position_id: @position.id }
    follow_redirect!
    assert_select "dialog#shift-converted-modal", count: 0

    travel 6.hours
    post me_shift_manage_end_path
    follow_redirect!
    assert_select "dialog#shift-converted-modal", count: 0
    assert_equal Person::ACTIVE, @person.reload.status
  end

  test "ending a very short shift offers the too-short options first" do
    entry = start_shift!
    travel 5.minutes

    post me_shift_manage_end_path, params: { entry_id: entry.id }

    assert_response :success
    assert_match "might be too short", response.body
    assert_nil entry.reload.off_duty

    post me_shift_manage_end_path, params: { entry_id: entry.id, confirmed: 1 }
    assert_redirected_to me_shift_manage_path
    assert_equal Current.time, entry.reload.off_duty
  end

  test "a stale entry id is rejected" do
    entry = start_shift!

    post me_shift_manage_end_path, params: { entry_id: entry.id + 1 }

    assert_redirected_to me_shift_manage_path
    assert_match "changed since the page was loaded", flash[:error]
    assert_nil entry.reload.off_duty
  end

  test "the correct position flow renders the modal and updates the entry" do
    entry = start_shift!
    replacement = Position.create!(title: "Replacement Position", active: true, no_training_required: true)
    PersonPosition.create!(person_id: @person.id, position_id: replacement.id)

    get me_shift_manage_position_path
    assert_response :success
    assert_match "Correct Shift Position", response.body
    # The modal renders inside the "modal" turbo-frame; its form must escape
    # the frame or the success redirect never updates the page.
    assert_match 'data-turbo-frame="_top"', response.body

    patch me_shift_manage_position_path, params: { entry_id: entry.id, position_id: replacement.id }
    assert_redirected_to me_shift_manage_path
    assert_equal replacement.id, entry.reload.position_id
  end

  test "a just-ended shift offers resume, and resignin puts the person back on duty" do
    entry = start_shift!
    travel 2.hours
    ShiftManage.sign_off(entry, user: @person)

    get me_shift_manage_path
    assert_response :success
    assert_match "Accidentally ended the shift?", response.body

    post me_shift_manage_resignin_path, params: { entry_id: entry.id }

    assert_redirected_to me_shift_manage_path
    assert_nil entry.reload.off_duty
    assert_equal entry.id, Timesheet.find_person_on_duty(@person.id).id
  end

  test "delete mistake removes the accidental entry" do
    entry = start_shift!

    delete me_shift_manage_entry_path, params: { entry_id: entry.id }

    assert_redirected_to me_shift_manage_path
    assert_nil Timesheet.find_by(id: entry.id)
    assert TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::DELETE_MISTAKE).exists?
  end

  private

  def start_shift!
    entry = Timesheet.new(person_id: @person.id, position_id: @position.id, on_duty: Current.time)
    entry.save!(validate: false)
    entry
  end
end
