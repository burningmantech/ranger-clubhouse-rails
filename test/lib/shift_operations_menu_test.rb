# frozen_string_literal: true

require "test_helper"

# The Shift Operations category gate, which was dropped when Bulk Sign In/Out
# landed beside Mass Sign-Out with a wider gate than its sibling's.
#
# Worth a test of its own because the failure is invisible: with a category-level
# `visible_if: { roles: [Role::ADMIN] }` back in place, every assertion about the
# page itself still passes and the item simply never appears in the mega menu for
# the readers it was built for.
class ShiftOperationsMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::PAYROLL, "Payroll")
    @person = person(:active_ranger)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "the category itself carries no role gate" do
    assert_nil Menus::SHIFT_OPERATIONS[:visible_if],
               "a category gate here would have to be a union of its items' gates, " \
               "which goes stale silently -- MegaMenu already hides an empty category"
  end

  test "timesheet management sees Bulk Sign In/Out in the mega menu" do
    titles = mega_menu_titles_for(Role::TIMESHEET_MANAGEMENT)

    assert_includes titles, "Bulk Sign In/Out"
  end

  test "timesheet management does not see the admin-only Mass Sign-Out" do
    titles = mega_menu_titles_for(Role::TIMESHEET_MANAGEMENT)

    # The positive half keeps the absence honest: with the category gone
    # entirely, titles is empty and the assertion below passes for the wrong
    # reason -- which is the exact failure this file exists to catch.
    assert_includes titles, "Bulk Sign In/Out"
    assert_not_includes titles, "Mass Sign-Out"
  end

  test "an admin sees every page" do
    titles = mega_menu_titles_for(Role::ADMIN)

    assert_includes titles, "Mass Sign-Out"
    assert_includes titles, "Bulk Sign In/Out"
    assert_includes titles, "Roll Call"
    assert_includes titles, "ROC Photo Board"
    assert_includes titles, "Payroll Export"
    assert_includes titles, "Missing Paycom Employee IDs"
    assert_includes titles, "Cruise Direction"
  end

  # Payroll reaches nothing else in this category, and the roles that run the
  # rest of it have no business in the payroll file.
  test "payroll sees the payroll pages and nothing else here" do
    titles = mega_menu_titles_for(Role::PAYROLL)

    assert_includes titles, "Payroll Export"
    assert_includes titles, "Missing Paycom Employee IDs"
    assert_not_includes titles, "Mass Sign-Out"
    assert_not_includes titles, "Roll Call"
    assert_not_includes titles, "Bulk Sign In/Out"
    assert_not_includes titles, "Cruise Direction"
    assert_not_includes titles, "ROC Photo Board"
  end

  # Read from the controllers so the menu cannot drift from their authorize_role
  # lists, which are what gate the page each item links to: an item gated more
  # tightly than its page hides it from its readers, and one gated more loosely
  # links to a redirect. The per-role tests above only compare the menu with
  # itself; this is the one that notices a controller's gate moving alone.
  test "every item carries the gate its controller enforces" do
    MegaMenu.each_item(Menus::SHIFT_OPERATIONS[:sections]) do |item|
      route = Rails.application.routes.recognize_path(MegaMenu.resolve_path(item[:path]))
      controller = "#{route[:controller]}_controller".camelize.constantize

      assert_equal controller.authorized_roles.sort, item.dig(:visible_if, :roles).to_a.sort,
                   "#{item[:title]} is gated differently from #{controller.name}"
    end
  end

  test "timesheet management does not see the payroll pages" do
    titles = mega_menu_titles_for(Role::TIMESHEET_MANAGEMENT)

    assert_includes titles, "Bulk Sign In/Out"
    assert_not_includes titles, "Payroll Export"
    assert_not_includes titles, "Missing Paycom Employee IDs"
  end

  test "event management sees the photo board and nothing else here" do
    titles = mega_menu_titles_for(Role::EVENT_MANAGEMENT)

    assert_includes titles, "ROC Photo Board"
    assert_not_includes titles, "Mass Sign-Out"
    assert_not_includes titles, "Roll Call"
    assert_not_includes titles, "Cruise Direction"
  end

  test "timesheet management does not see the photo board" do
    titles = mega_menu_titles_for(Role::TIMESHEET_MANAGEMENT)

    assert_includes titles, "Bulk Sign In/Out"
    assert_not_includes titles, "ROC Photo Board"
  end

  test "shift management sees Roll Call and nothing else here" do
    titles = mega_menu_titles_for(Role::SHIFT_MANAGEMENT)

    # Same shape as the pair above: the positive assertion is what keeps the
    # two absences from passing because the category vanished entirely.
    assert_includes titles, "Roll Call"
    assert_not_includes titles, "Mass Sign-Out"
    assert_not_includes titles, "Bulk Sign In/Out"
    assert_not_includes titles, "Cruise Direction"
  end

  test "timesheet management does not see Roll Call" do
    titles = mega_menu_titles_for(Role::TIMESHEET_MANAGEMENT)

    assert_includes titles, "Bulk Sign In/Out"
    assert_not_includes titles, "Roll Call"
  end

  test "a Ranger with neither role sees no Shift Operations category at all" do
    assert_nil shift_operations_category(mega_menu_for(nil)),
               "an empty category must not render as a heading with nothing under it"
  end

  private

  # Menu role rules read Current.has_role?, which answers from the roles manager
  # rather than from Current.person -- setting the person alone leaves every
  # gated item invisible and every assertion here vacuously green.
  def mega_menu_for(role_id)
    grant_role(@person, role_id) if role_id
    Current.person = @person
    Current.roles_manager = RoleManager.retrieve(@person)
    MegaMenu.categories(person: @person, computed: {})
  end

  def shift_operations_category(categories)
    categories.find { |category| category[:title] == "Shift Operations" }
  end

  def mega_menu_titles_for(role_id)
    category = shift_operations_category(mega_menu_for(role_id))
    return [] unless category

    category[:sections].flat_map { |section| section[:items].to_a.map { |item| item[:title] } }
  end
end
