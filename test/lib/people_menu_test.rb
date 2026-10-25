# frozen_string_literal: true

require "test_helper"

# The People category, whose items admit different people.
#
# Worth its own test because both halves fail silently. The category gate has to
# be at least as wide as its widest item or the item never appears for anyone;
# widening it then hands every reader the whole category unless each item also
# carries its own gate.
class PeopleMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  BULK_STATUS = "Bulk Change Status"
  BULK_LOOKUP = "Bulk Lookup"
  BY_LOCATION = "People by Location"
  UNIFIED_FLAGGING = "Unified Flagging"

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::VC, "VC")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # Resolved through the menu's own entry: a mistyped path symbol in the
  # definition is exactly what this guards.
  test "the location report's menu item leads to the report" do
    linkable = MegaMenu.linkable_items(Menus::MEGA_CATEGORIES)

    assert_equal "/people/people-by-location",
                 linkable.find { |_path, item| item[:title] == BY_LOCATION }&.first
  end

  test "the bulk lookup menu item leads to the lookup page" do
    linkable = MegaMenu.linkable_items(Menus::MEGA_CATEGORIES)

    assert_equal "/people/bulk-lookup",
                 linkable.find { |_path, item| item[:title] == BULK_LOOKUP }&.first
  end

  test "the category itself carries no role gate" do
    assert_nil Menus::PEOPLE[:visible_if],
               "a category gate here would have to be a union of its items' gates, " \
               "which goes stale silently -- MegaMenu already hides an empty category"
  end

  # Read from the controllers so the menu cannot drift from their authorize_role
  # lists, which are what gate the page each item links to: an item gated more
  # tightly than its page hides it from its readers, and one gated more loosely
  # -- or not at all -- links to a redirect. The People sidebar builds from the
  # same items, so this covers it too.
  test "every item carries the gate its controller enforces" do
    MegaMenu.each_item(Menus::PEOPLE[:sections]) do |item|
      route = Rails.application.routes.recognize_path(MegaMenu.resolve_path(item[:path]))
      controller = "#{route[:controller]}_controller".camelize.constantize

      assert_equal controller.authorized_roles.sort, item.dig(:visible_if, :roles).to_a.sort,
                   "#{item[:title]} is gated differently from #{controller.name}"
    end
  end

  # The positive half keeps the absence honest: with the category gone entirely
  # the list is empty and the negative assertion would pass for the wrong reason.
  test "a reader of the location report is not offered the admin-only pages" do
    titles = titles_for(Role::TRAINER, person(:echelon_ranger))

    assert_includes titles, BY_LOCATION
    assert_not_includes titles, BULK_STATUS
    assert_not_includes titles, BULK_LOOKUP
    assert_not_includes titles, UNIFIED_FLAGGING
  end

  # An Event Management gate on the category used to hide all of these from an
  # Admin who did not also hold it, which is most of them.
  test "an admin sees the admin-only pages" do
    titles = titles_for(Role::ADMIN, person(:active_ranger))

    assert_includes titles, BULK_STATUS
    assert_includes titles, BULK_LOOKUP
    assert_includes titles, BY_LOCATION
    assert_includes titles, "Create Account"
    assert_includes titles, "People Search"
    assert_includes titles, "Languages Known"
    assert_includes titles, UNIFIED_FLAGGING
  end

  # Languages Known is the one page this role reads, and the category gate that
  # briefly lived here was its role -- so this was the only reader it did not
  # shut out, and the one case that kept the old gate looking harmless.
  test "event management sees Languages Known and nothing else here" do
    titles = titles_for(Role::EVENT_MANAGEMENT, person(:auditor_ranger))

    assert_includes titles, "Languages Known"
    assert_not_includes titles, BULK_STATUS
    assert_not_includes titles, BY_LOCATION
  end

  # The category carries no gate of its own -- it disappears because every item
  # in it is hidden. That only holds while the items stay gated, so it is
  # asserted rather than assumed.
  test "a reader with none of the roles is offered no People category at all" do
    holder = person(:inactive_ranger)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    titles = MegaMenu.categories(person: holder, computed: {}).map { |entry| entry[:title] }

    assert_not_includes titles, "People"
  end

  private

  # Menu role rules read Current.has_role?, which answers from the roles manager
  # rather than from Current.person -- setting the person alone leaves every
  # gated item invisible and every assertion here vacuously green.
  def titles_for(role_id, holder)
    grant_role(holder, role_id)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    category = MegaMenu.categories(person: holder, computed: {})
                       .find { |entry| entry[:title] == "People" }
    return [] unless category

    category[:sections].flat_map { |section| section[:items].to_a.map { |item| item[:title] } }
  end
end
