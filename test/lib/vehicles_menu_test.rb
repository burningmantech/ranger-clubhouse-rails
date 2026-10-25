# frozen_string_literal: true

require "test_helper"

# The Vehicles category, whose three items admit three different sets of people
# and whose gates turn on a setting.
#
# No controller-parity test like Administration's: all three pages gate with
# authorize_ability rather than authorize_role, so `authorized_roles` is nil for
# every one of them and there is no list to compare against. These assert the
# behaviour instead, which is what drifted -- the Paperwork item listed the raw
# Event Management On Playa role, so its holder was shown the link all year and
# turned away from it for the nine months the on-playa setting is off.
class VehiclesMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  CATEGORY = "Vehicles"
  REGISTRY = "Vehicle Registry"
  PAPERWORK = "Vehicle Paperwork"
  BULK = "Bulk Vehicle Paperwork"

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EVENT_MANAGEMENT_ON_PLAYA, "Event Management On Playa")
    ensure_role(Role::VEHICLE_MANAGEMENT, "Vehicle Management")
    ensure_role(Role::VEHICLE_INFO_UPDATE, "Vehicle Info Update")
    set_on_playa(false)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "the category itself carries no role gate" do
    assert_nil Menus::VEHICLES[:visible_if],
               "the gate here was the union of the items' roles, which has to be kept in step " \
               "by hand and fails silently when it is not -- MegaMenu already hides an empty category"
  end

  # RoleManager drops the raw on-playa role off-season, and while the setting is
  # on upgrades its holder to Event Management, so they get both pages or none.
  test "on-playa event management is offered neither report off-season" do
    titles = titles_for(Role::EVENT_MANAGEMENT_ON_PLAYA, person(:echelon_ranger))

    assert_not_includes titles, REGISTRY
    assert_not_includes titles, PAPERWORK
    assert_not_includes titles, BULK
  end

  test "on-playa event management is offered paperwork once the setting is on" do
    set_on_playa(true)

    titles = titles_for(Role::EVENT_MANAGEMENT_ON_PLAYA, person(:echelon_ranger))

    assert_includes titles, REGISTRY
    assert_includes titles, PAPERWORK
  end

  # Year-round Event Management, for contrast with the pair above: the setting
  # is off here and this reader still gets both pages.
  test "event management is offered both reports whatever the season" do
    titles = titles_for(Role::EVENT_MANAGEMENT, person(:auditor_ranger))

    assert_includes titles, REGISTRY
    assert_includes titles, PAPERWORK
    assert_not_includes titles, BULK
  end

  # The two single-page roles. Each was the reason a different role had to be
  # named in the old category union.
  test "vehicle management sees only the bulk page" do
    titles = titles_for(Role::VEHICLE_MANAGEMENT, person(:inactive_ranger))

    assert_includes titles, BULK
    assert_not_includes titles, REGISTRY
    assert_not_includes titles, PAPERWORK
  end

  test "vehicle info update sees only paperwork" do
    titles = titles_for(Role::VEHICLE_INFO_UPDATE, person(:retired_ranger))

    assert_includes titles, PAPERWORK
    assert_not_includes titles, REGISTRY
    assert_not_includes titles, BULK
  end

  test "an admin sees all three" do
    titles = titles_for(Role::ADMIN, person(:active_ranger))

    assert_includes titles, REGISTRY
    assert_includes titles, PAPERWORK
    assert_includes titles, BULK
  end

  # The category disappears because every item in it is hidden. That only holds
  # while the items stay gated, so it is asserted rather than assumed.
  test "a person with none of the roles sees no Vehicles category at all" do
    holder = person(:prospective_ranger)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    titles = MegaMenu.categories(person: holder, computed: {}).map { |entry| entry[:title] }

    assert_not_includes titles, CATEGORY
  end

  private

  # RoleManager reads this setting while it builds the role set, so it has to be
  # written before the roles are retrieved, not after.
  def set_on_playa(enabled)
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED)
           .update!(value: enabled.to_s)
  end

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
