# frozen_string_literal: true

require "application_system_test_case"

# The year selector in a hero panel (PageLayoutHelper#year_selector_compact).
class YearSelectorTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper

  setup do
    @person = person(:active_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@person, Role::ADMIN)
    sign_in(@person)
  end

  # Turbo's copy of the page for Back keeps a select's live choice, so the
  # restored page read the year it was changed to over the old year's roster
  # and Export All to CSV link.
  test "Back restores the page's own year in the selector" do
    visit timesheets_timesheet_totals_report_path(year: 2023)
    wait_for_controller("form", "form:has(#year-selector-compact)")
    select "2022", from: "year-selector-compact"
    assert_selector "h1", text: "2022 Timesheet Totals"

    page.go_back
    assert_selector "h1", text: "2023 Timesheet Totals"
    assert_field "year-selector-compact", with: "2023"
  end
end
