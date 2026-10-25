# frozen_string_literal: true

require "application_system_test_case"

# The select-all box beside a row it passes over. It used to untick itself
# after every click -- "all" counted the stale row, which select-all never
# ticks -- so a second click selected again instead of clearing.
class ShiftOperations::MassSignoutSelectAllTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  TOGGLE = "[data-checkbox-select-all-target=toggle]"

  setup do
    admin = person(:active_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(admin, Role::ADMIN)

    ood = positions(:ood_position)
    @current = Timesheet.create!(person: admin, position: ood, on_duty: 2.hours.ago,
                                 additional_notes: "test shift")
    @stale = Timesheet.create!(person: person(:echelon_ranger), position: ood, on_duty: 3.years.ago,
                               additional_notes: "test shift")
    sign_in(admin)
  end

  test "beside a skipped row select all starts ticked, clears, then selects again" do
    visit shift_operations_mass_signout_path

    # Every entry select-all can arm starts ticked, so the box says so.
    assert_selector "#{TOGGLE}:checked"

    find(TOGGLE).click
    assert_no_selector "#{TOGGLE}:checked"
    assert_no_selector "[data-checkbox-select-all-target=checkbox]:checked"

    find(TOGGLE).click
    assert_selector "#{TOGGLE}:checked"
    assert_selector "#mass-signout-check-#{@current.id}:checked"
    assert_no_selector "#mass-signout-check-#{@stale.id}:checked"
  end
end
