# frozen_string_literal: true

require "test_helper"

# The Administration category gate, which was dropped because its items admit
# different people: Settings is Admin-only, OAuth Clients is Tech Ninja-only, and
# neither role implies the other.
#
# Worth a test of its own because both halves fail silently. With a category-level
# `visible_if: { roles: [Role::ADMIN] }` back in place, every assertion about the
# pages themselves still passes and a Tech Ninja simply never finds them in the
# mega menu. With it gone, an item that carries no gate of its own is offered to
# every Ranger.
class AdminMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

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

  test "the category itself carries no role gate" do
    assert_nil Menus::ADMIN[:visible_if],
               "a category gate here would have to be a union of its items' gates, " \
               "which goes stale silently -- MegaMenu already hides an empty category"
  end

  # Read from the controllers so the menu cannot drift from their authorize_role
  # lists, which are what gate the index each item links to: an item gated more
  # tightly than its page hides it from its readers, and one gated more loosely
  # -- or not at all -- links to a redirect. The admin sidebar builds from the
  # same items, so this covers it too.
  test "every item carries the gate its controller enforces" do
    MegaMenu.each_item(Menus::ADMIN[:sections]) do |item|
      route = Rails.application.routes.recognize_path(MegaMenu.resolve_path(item[:path]))
      controller = "#{route[:controller]}_controller".camelize.constantize

      assert_equal controller.authorized_roles.sort, item.dig(:visible_if, :roles).to_a.sort,
                   "#{item[:title]} is gated differently from #{controller.name}"
    end
  end

  test "a tech ninja who is not an admin sees the category, minus the admin-only pages" do
    category = administration_for(person(:echelon_ranger), Role::TECH_NINJA)

    assert_not_nil category, "the category is hidden from a Tech Ninja, and with it every page gated for them"

    # OAuth Clients is the page the old Admin-only category gate hid outright:
    # it admits Tech Ninja alone, so nobody without both roles could reach it.
    titles = titles_in(category)
    assert_includes titles, "OAuth Clients"
    assert_includes titles, "Salesforce Query"
    assert_includes titles, "Error Logs"
    assert_includes titles, "Shift Coverage Setup"
    assert_not_includes titles, "Settings"
  end

  test "an admin still sees the admin-only pages" do
    titles = titles_in(administration_for(person(:active_ranger), Role::ADMIN))

    assert_includes titles, "Documents"
    assert_includes titles, "Online Courses"
    assert_includes titles, "Settings"
    assert_includes titles, "Action Logs"
    assert_includes titles, "Mail Log"
    assert_includes titles, "Shift Coverage Setup"
    # Tech Ninja only: Admin alone does not open it.
    assert_not_includes titles, "Salesforce Query"
  end

  # The category disappears because every item in it is hidden. That only holds
  # while the items stay gated, so it is asserted rather than assumed.
  test "a person with neither role sees no Administration category at all" do
    assert_nil administration_for(person(:inactive_ranger))
  end

  private

  # Menu role rules read Current.has_role?, which answers from the roles manager
  # rather than from Current.person -- setting the person alone leaves every
  # gated item invisible and every assertion here vacuously green.
  def administration_for(holder, role_id = nil)
    grant_role(holder, role_id) if role_id
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    MegaMenu.categories(person: holder, computed: {}).find { |entry| entry[:title] == "Administration" }
  end

  def titles_in(category)
    titles = []
    MegaMenu.each_item(category[:sections]) { |item| titles << item[:title] }
    titles
  end
end
