# frozen_string_literal: true

require "test_helper"

# The Pogs category: two pages for Admin and Pog Management, and nobody else.
# Event Management is the realistic wrong-role probe -- it owns Person › Pogs
# and the HQ pog flow, and must not be offered these.
class PogsMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::POG_MANAGEMENT, "Pog Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # Read from the controllers, so the menu cannot drift from what gates the pages.
  test "every item carries the gate its controller enforces" do
    MegaMenu.each_item(Menus::POGS[:sections]) do |item|
      route = Rails.application.routes.recognize_path(MegaMenu.resolve_path(item[:path]))
      controller = "#{route[:controller]}_controller".camelize.constantize

      assert_equal controller.authorized_roles.sort, item.dig(:visible_if, :roles).sort,
                   "#{item[:title]} is gated differently from #{controller.name}"
    end
  end

  test "pog management is offered both pages" do
    assert_equal ["Pog Dashboard", "Pog Administration"],
                 titles_for(Role::POG_MANAGEMENT, person(:inactive_ranger))
  end

  test "event management is offered no Pogs category" do
    assert_empty titles_for(Role::EVENT_MANAGEMENT, person(:auditor_ranger))
  end

  private

  # Menu rules read Current.has_role?, which answers from the roles manager
  # rather than from Current.person.
  def titles_for(role_id, holder)
    grant_role(holder, role_id)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    category = MegaMenu.categories(person: holder, computed: {}).find { |entry| entry[:title] == "Pogs" }
    return [] unless category

    titles = []
    MegaMenu.each_item(category[:sections]) { |item| titles << item[:title] }
    titles
  end
end
