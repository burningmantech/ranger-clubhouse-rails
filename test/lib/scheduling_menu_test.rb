# frozen_string_literal: true

require "test_helper"

# The Scheduling category's Forecast Reports section, which the Shift Lead
# Report is the first item of.
#
# Worth its own test because the failure is invisible: a mistyped path helper or
# a gate naming a role no one holds leaves every assertion about the page itself
# passing while the item simply never appears in the mega menu.
class SchedulingMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  ITEM = "Shift Lead Report"
  SCHEDULE_ITEM = "Schedule by Callsign"
  FORECAST_ITEM = "HQ Check In/Out Forecast"
  EVENT_STATS_ITEM = "Event Statistics"
  SANDMAN_ITEM = "Sandman Qualifications"

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    ensure_role(Role::VC, "Volunteer Coordinator")
    @person = person(:active_ranger)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "the item's path helper resolves" do
    assert_equal "/scheduling/shift-lead",
                 Rails.application.routes.url_helpers.scheduling_shift_lead_path
  end

  test "event management sees the Shift Lead Report" do
    assert_includes titles_for(Role::EVENT_MANAGEMENT), ITEM
  end

  test "an admin sees the Shift Lead Report" do
    assert_includes titles_for(Role::ADMIN), ITEM
  end

  # The positive half keeps the absence honest: with the category gone entirely
  # the list is empty and the negative assertion passes for the wrong reason.
  test "a role outside the report's gate does not see it" do
    titles = titles_for(Role::EDIT_SLOTS)

    assert_includes titles, "Slots"
    assert_not_includes titles, ITEM
  end

  # --- Schedule by Callsign, the section's second item --------------------

  test "the schedule by callsign path helper resolves" do
    assert_equal "/scheduling/schedule-by-callsign",
                 Rails.application.routes.url_helpers.scheduling_schedule_by_callsign_path
  end

  # The menu gate has to admit the same three roles the controller does, or the
  # page is reachable only by typing the URL.
  test "every role that may read the schedule by callsign sees the item" do
    [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::EDIT_SLOTS].each do |role_id|
      Current.reset
      @person = person(:active_ranger)
      assert_includes titles_for(role_id), SCHEDULE_ITEM,
                      "role #{role_id} reads the report but cannot see the menu item"
    end
  end

  test "a role outside the schedule by callsign gate does not see it" do
    titles = titles_for(Role::VC)

    assert_not_includes titles, SCHEDULE_ITEM
  end

  test "the HQ forecast path helper resolves" do
    assert_equal "/scheduling/hq-forecast",
                 Rails.application.routes.url_helpers.scheduling_hq_forecast_path
  end

  test "every role that may read the HQ forecast sees the item" do
    [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::EDIT_SLOTS].each do |role_id|
      Current.reset
      @person = person(:active_ranger)
      assert_includes titles_for(role_id), FORECAST_ITEM,
                      "role #{role_id} reads the report but cannot see the menu item"
    end
  end

  # The category carries no gate of its own, so an item without one would show
  # for everyone signed in.
  test "a role outside the HQ forecast gate does not see it" do
    assert_not_includes titles_for(Role::VC), FORECAST_ITEM
  end

  # --- Sandman Qualifications, the section's last item ---------------------

  test "the sandman qualifications path helper resolves" do
    assert_equal "/scheduling/sandman-qualified",
                 Rails.application.routes.url_helpers.scheduling_sandman_qualified_path
  end

  test "every role that may read the sandman report sees the item" do
    [Role::ADMIN, Role::EVENT_MANAGEMENT].each do |role_id|
      Current.reset
      @person = person(:active_ranger)
      assert_includes titles_for(role_id), SANDMAN_ITEM,
                      "role #{role_id} reads the report but cannot see the menu item"
    end
  end

  # A narrower gate than the reports beside it, so Edit Slots is the case worth
  # holding: it sees the section and still must not see this item.
  test "edit slots does not see the sandman qualifications" do
    titles = titles_for(Role::EDIT_SLOTS)

    assert_includes titles, "Slots"
    assert_not_includes titles, SANDMAN_ITEM
  end

  # --- Event Statistics, the category's own section -----------------------

  test "the event stats path helper resolves" do
    assert_equal "/scheduling/event-stats",
                 Rails.application.routes.url_helpers.scheduling_event_stats_path
  end

  test "every role that may read the event stats sees the item" do
    [Role::ADMIN, Role::EVENT_MANAGEMENT].each do |role_id|
      Current.reset
      @person = person(:active_ranger)
      assert_includes titles_for(role_id), EVENT_STATS_ITEM,
                      "role #{role_id} reads the report but cannot see the menu item"
    end
  end

  # A narrower gate than the reports beside it, so Edit Slots is the case worth
  # holding: it sees the category and still must not see this item.
  test "edit slots does not see the event stats" do
    titles = titles_for(Role::EDIT_SLOTS)

    assert_includes titles, "Slots"
    assert_not_includes titles, EVENT_STATS_ITEM
  end

  private

  # Menu role rules read Current.has_role?, which answers from the roles manager
  # rather than from Current.person -- setting the person alone leaves every
  # gated item invisible and every assertion here vacuously green.
  def titles_for(role_id)
    grant_role(@person, role_id)
    Current.person = @person
    Current.roles_manager = RoleManager.retrieve(@person)

    category = MegaMenu.categories(person: @person, computed: {})
                       .find { |entry| entry[:title] == "Scheduling" }
    return [] unless category

    category[:sections].flat_map { |section| section[:items].to_a.map { |item| item[:title] } }
  end
end
