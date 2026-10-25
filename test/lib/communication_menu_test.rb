# frozen_string_literal: true

require "test_helper"

# The Communication Management category's Survey Management item.
#
# Worth its own test because the item is gated by a rule no list of role ids
# can express: a survey permission is often composed for one training, so the
# item asks Survey.can_manage_any? instead. A gate that answered false for
# everyone would hide the page from the people who run it, and one that
# answered true would offer it to the whole Clubhouse.
class CommunicationMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  SURVEYS = "Survey Management"

  setup do
    Rails.cache.clear
    Current.reset

    Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                     type: Position::TYPE_TRAINING, active: true)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::SURVEY_MANAGEMENT_TRAINING, "Survey Management")
    ensure_role(Role::SURVEY_MANAGEMENT_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Survey Mgmt")
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "the menu item leads to the survey management page" do
    linkable = MegaMenu.linkable_items(Menus::MEGA_CATEGORIES)

    assert_equal "/communication/survey-management",
                 linkable.find { |_path, item| item[:title] == SURVEYS }&.first
  end

  test "every kind of survey role sees the item" do
    { Role::ADMIN => person(:active_ranger),
      Role::SURVEY_MANAGEMENT_TRAINING => person(:echelon_ranger),
      (Role::SURVEY_MANAGEMENT_BASE | Position::GREEN_DOT_TRAINING) => person(:retired_ranger) }
      .each do |role_id, holder|
      Current.reset

      assert_includes titles_for(role_id, holder), SURVEYS,
                      "role #{role_id} manages surveys but cannot see the menu item"
    end
  end

  test "someone with no survey role is not offered it" do
    holder = person(:inactive_ranger)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    assert_not_includes category_titles(holder), SURVEYS
  end

  private

  # Menu rules read Current.has_role?, which answers from the roles manager
  # rather than from Current.person -- setting the person alone leaves every
  # gated item invisible and every assertion here vacuously green.
  def titles_for(role_id, holder)
    grant_role(holder, role_id)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    category_titles(holder)
  end

  def category_titles(holder)
    category = MegaMenu.categories(person: holder, computed: {})
                       .find { |entry| entry[:title] == "Communication Management" }
    return [] unless category

    category[:sections].flat_map { |section| section[:items].to_a.map { |item| item[:title] } }
  end
end
