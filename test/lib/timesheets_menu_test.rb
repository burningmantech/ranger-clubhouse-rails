# frozen_string_literal: true

require "test_helper"

# The Timesheets category's Reports section, and the items in it that only Admin
# and Timesheet Management may read.
#
# Worth its own test because the failure is invisible: a mistyped path helper or
# a gate naming a role no one holds leaves every assertion about the page itself
# passing while the item simply never appears in the mega menu.
class TimesheetsMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  ITEMS = { "Top Hour Earners" => "/timesheets/top-hour-earners",
            "Hours & Credits" => "/timesheets/hours-credits" }.freeze

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    @person = person(:active_ranger)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # Resolved through the menu's own entry rather than by naming the route helper
  # here: a mistyped path symbol in the definition is the failure this guards,
  # and calling the helper directly would only restate the routes file.
  test "each item's path resolves to its report" do
    linkable = MegaMenu.linkable_items(Menus::MEGA_CATEGORIES)

    ITEMS.each do |title, path|
      assert_equal path, linkable.find { |_path, item| item[:title] == title }&.first,
                   "#{title} does not lead to its report"
    end
  end

  # A person apiece. Roles are granted, never revoked, so running both roles
  # through one person would leave the second pass still holding the first
  # role -- and the items would appear for a reason the test is not asserting.
  test "every role that may read the reports sees the items" do
    { Role::ADMIN => person(:active_ranger),
      Role::TIMESHEET_MANAGEMENT => person(:auditor_ranger) }.each do |role_id, holder|
      Current.reset
      titles = titles_for(role_id, holder)

      ITEMS.each_key do |item|
        assert_includes titles, item,
                        "role #{role_id} reads #{item} but cannot see the menu item"
      end
    end
  end

  # The positive half keeps the absence honest: with the category gone entirely
  # the list is empty and the negative assertions pass for the wrong reason.
  # Event Management reads most of this category but not these reports.
  test "a role outside the reports' gate does not see them" do
    titles = titles_for(Role::EVENT_MANAGEMENT)

    assert_includes titles, "On Duty"
    ITEMS.each_key { |item| assert_not_includes titles, item }
  end

  private

  # Menu role rules read Current.has_role?, which answers from the roles manager
  # rather than from Current.person -- setting the person alone leaves every
  # gated item invisible and every assertion here vacuously green.
  def titles_for(role_id, holder = @person)
    grant_role(holder, role_id)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    category = MegaMenu.categories(person: holder, computed: {})
                       .find { |entry| entry[:title] == "Timesheets" }
    return [] unless category

    category[:sections].flat_map { |section| section[:items].to_a.map { |item| item[:title] } }
  end
end
