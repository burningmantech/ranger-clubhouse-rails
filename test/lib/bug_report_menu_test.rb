# frozen_string_literal: true

require "test_helper"

# The menu entry for the log the Tech Team reads. Filing a report has no menu
# entry: its button is on the top menu bar itself, at every width.
class BugReportMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  BUG_REPORTS = "Bug Reports"

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "the log's menu item leads to the log and shows for a tech ninja only" do
    linkable = MegaMenu.linkable_items(Menus::MEGA_CATEGORIES)
    assert_equal "/admin/bug-reports", linkable.find { |_path, item| item[:title] == BUG_REPORTS }&.first

    assert_includes admin_titles_for(person(:echelon_ranger), Role::TECH_NINJA), BUG_REPORTS
    assert_not_includes admin_titles_for(person(:active_ranger), Role::ADMIN), BUG_REPORTS
  end

  private

  # The titles the Administration menu builds for someone holding one role.
  # Built from the sections, as the admin sidebar does; AdminMenuTest covers the
  # category as the mega menu builds it.
  def admin_titles_for(person, role)
    grant_role(person, role)
    Current.person = person
    Current.roles_manager = RoleManager.retrieve(person)

    titles = []
    MegaMenu.each_item(MenuBuilder.build(Menus::ADMIN, { person:, computed: {} })) { |item| titles << item[:title] }
    titles
  end
end
