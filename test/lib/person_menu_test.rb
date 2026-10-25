# frozen_string_literal: true

require "test_helper"

# The person menu's Site Log item is offered to exactly the roles its page
# admits, so no one is shown a link that turns them away.
class PersonMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  SITE_LOG = "Site Log"

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EVENT_MANAGEMENT_ON_PLAYA, "Event Management On Playa")
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "the site log item is gated on exactly the roles its page admits" do
    item = Menus::PERSON[:sections].flat_map { it[:items] }.find { it[:title] == SITE_LOG }

    assert_equal Person::SiteLogController.authorized_roles.sort, item.dig(:visible_if, :roles).sort
  end

  test "the site log item shows for admin and event management, and not for a mentor" do
    assert_includes titles_for(person(:auditor_ranger), Role::ADMIN), SITE_LOG
    assert_includes titles_for(person(:echelon_ranger), Role::EVENT_MANAGEMENT), SITE_LOG
    # RoleManager keeps the on-playa role only while its setting is on.
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: "true")
    assert_includes titles_for(person(:retired_ranger), Role::EVENT_MANAGEMENT_ON_PLAYA), SITE_LOG
    assert_not_includes titles_for(person(:ranger_with_custom_gender), Role::MENTOR), SITE_LOG
  end

  private

  # The titles the person sidebar builds for someone holding one role.
  def titles_for(person, role)
    grant_role(person, role)
    Current.person = person
    Current.roles_manager = RoleManager.retrieve(person)

    titles = []
    MegaMenu.each_item(MenuBuilder.build(Menus::PERSON, { person:, computed: {} })) { |item| titles << item[:title] }
    titles
  end
end
