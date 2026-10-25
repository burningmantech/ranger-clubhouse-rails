# frozen_string_literal: true

require "test_helper"

# The Volunteer Coordinator category, whose items admit different people: most
# of it is VC's own work, but four pages belong to a role that reaches nothing
# else here -- Intake, Edit Handle Reservations, and Salesforce Import.
#
# Worth its own test because both halves fail silently. The Admin-or-VC gate the
# category used to carry hid those four pages from exactly the people they were
# built for, and every page still answered correctly for anyone who typed its
# URL. Drop an item's gate instead and the VC sidebar -- which never reads a
# category gate -- offers that page to every reader of the others.
class VcMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  CATEGORY = "Volunteer Coordinator"
  RESERVED_HANDLES = "Reserved Handles"
  UNIFIED_FLAGGING = "Unified Flagging"
  APPLICATION_IMPORT = "Application Import"
  APPLICATIONS = "Applications"
  MAINTENANCE = "Maintenance"
  BPGUID_LOOKUP = "BPGUID Lookup"

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "VC")
    ensure_role(Role::INTAKE, "Intake")
    ensure_role(Role::EDIT_HANDLE_RESERVATIONS, "Edit Handle Reservations")
    ensure_role(Role::SALESFORCE_IMPORT, "Salesforce Import")
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "the category itself carries no role gate" do
    assert_nil Menus::VC[:visible_if],
               "a category gate here would have to be a union of its items' gates, " \
               "which goes stale silently -- MegaMenu already hides an empty category"
  end

  # Read from the controllers so the menu cannot drift from their authorize_role
  # lists, which are what gate the page each item links to: an item gated more
  # tightly than its page hides it from its readers, and one gated more loosely
  # -- or not at all -- links to a redirect. The VC sidebar builds from the same
  # items, so this covers it too.
  test "every item carries the gate its controller enforces" do
    MegaMenu.each_item(Menus::VC[:sections]) do |item|
      route = Rails.application.routes.recognize_path(MegaMenu.resolve_path(item[:path]))
      controller = "#{route[:controller]}_controller".camelize.constantize

      assert_equal controller.authorized_roles.sort, item.dig(:visible_if, :roles).to_a.sort,
                   "#{item[:title]} is gated differently from #{controller.name}"
    end
  end

  # The three roles the old category gate shut out entirely. Each reads one
  # corner of the category and nothing else, so the negative assertions say the
  # gates did not simply get dropped.
  test "intake sees the pipeline it files notes on, and nothing else here" do
    titles = titles_for(Role::INTAKE, person(:echelon_ranger))

    assert_includes titles, UNIFIED_FLAGGING
    assert_not_includes titles, APPLICATIONS
    assert_not_includes titles, MAINTENANCE
    assert_not_includes titles, BPGUID_LOOKUP
  end

  test "edit handle reservations sees the reserved list, and nothing else here" do
    titles = titles_for(Role::EDIT_HANDLE_RESERVATIONS, person(:inactive_ranger))

    assert_includes titles, RESERVED_HANDLES
    assert_not_includes titles, UNIFIED_FLAGGING
    assert_not_includes titles, APPLICATIONS
    assert_not_includes titles, BPGUID_LOOKUP
  end

  test "salesforce import sees the two import pages, and nothing else here" do
    titles = titles_for(Role::SALESFORCE_IMPORT, person(:retired_ranger))

    assert_includes titles, APPLICATION_IMPORT
    assert_includes titles, "Create Prospectives"
    assert_not_includes titles, APPLICATIONS
    assert_not_includes titles, RESERVED_HANDLES
    assert_not_includes titles, BPGUID_LOOKUP
  end

  # VC reads the reserved list but may not change it, so the item is theirs too.
  test "a vc sees their own pages but not the import pages" do
    titles = titles_for(Role::VC, person(:active_ranger))

    assert_includes titles, APPLICATIONS
    assert_includes titles, RESERVED_HANDLES
    assert_includes titles, UNIFIED_FLAGGING
    assert_includes titles, MAINTENANCE
    assert_includes titles, BPGUID_LOOKUP
    assert_not_includes titles, APPLICATION_IMPORT
  end

  test "an admin sees every page" do
    titles = titles_for(Role::ADMIN, person(:auditor_ranger))

    assert_includes titles, APPLICATIONS
    assert_includes titles, APPLICATION_IMPORT
    assert_includes titles, RESERVED_HANDLES
    assert_includes titles, UNIFIED_FLAGGING
    assert_includes titles, "Photo Review"
    assert_includes titles, "Thank You Cards"
    assert_includes titles, BPGUID_LOOKUP
  end

  # The category disappears because every item in it is hidden. That only holds
  # while the items stay gated, so it is asserted rather than assumed.
  test "a person with none of the roles sees no VC category at all" do
    holder = person(:prospective_ranger)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    titles = MegaMenu.categories(person: holder, computed: {}).map { |entry| entry[:title] }

    assert_not_includes titles, CATEGORY
  end

  private

  # Menu role rules read Current.has_role?, which answers from the roles manager
  # rather than from Current.person -- setting the person alone leaves every
  # gated item invisible and every assertion here vacuously green.
  def titles_for(role_id, holder)
    grant_role(holder, role_id)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    category = MegaMenu.categories(person: holder, computed: {}).find { |entry| entry[:title] == CATEGORY }
    return [] unless category

    titles = []
    MegaMenu.each_item(category[:sections]) { |item| titles << item[:title] }
    titles
  end
end
