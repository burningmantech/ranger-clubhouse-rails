# frozen_string_literal: true

require "test_helper"

# Pins the role gate PersonConcern applies to every /person/:id page.
#
# Shift Management is admitted so HQ Window workers can follow the HQ sidebar
# link-outs. That grant is deliberately app-wide across PersonConcern, so these
# tests also pin its boundary: the pages that layer their own authorize_role or
# authorize_ability on top stay closed to Shift Management alone.
class PersonConcernTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)
    @viewer = person(:auditor_ranger)

    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@viewer, Role::SHIFT_MANAGEMENT)
  end

  teardown do
    Rails.cache.clear
  end

  test "shift management alone opens a PersonConcern page" do
    sign_in_as(@viewer)

    get person_scheduling_path(@target, year: Current.year)

    assert_response :success
  end

  # PersonTimesheetConcern declares its own authorize_role, and authorize_role
  # is last-call-wins — so it replaces the PersonConcern list rather than
  # extending it, and Shift Management does not reach the timesheet page.
  test "shift management alone does not open the timesheet page" do
    sign_in_as(@viewer)

    get person_timesheets_path(@target, year: Current.year)

    assert_redirected_to me_root_path
  end

  test "a person with none of the gate roles is still refused" do
    stranger = person(:ranger_with_custom_gender)
    sign_in_as(stranger)

    get person_scheduling_path(@target, year: Current.year)

    assert_redirected_to me_root_path
  end
end
