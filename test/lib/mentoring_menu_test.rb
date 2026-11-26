# frozen_string_literal: true

require "test_helper"

# The Mentoring category: one gate for every page, read by Admin, Mentor
# Interface and -- while Event Management On Playa is on -- Mentor Interface
# Event. The controllers keep that list inline, so this is what stops one of
# them, or the menu, drifting from the rest.
class MentoringMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::MENTOR_INTERFACE_EVENT, "Mentor Interface Event")
    @holder = person(:inactive_ranger)
    grant_role(@holder, Role::MENTOR_INTERFACE_EVENT)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # Read from the files, so a controller added later is held to the same gate.
  test "every mentoring controller enforces the category's gate" do
    gate = Menus::MENTORING.dig(:visible_if, :roles)
    assert_includes gate, Role::MENTOR_INTERFACE_EVENT

    root = Rails.root.join("app/controllers")
    controllers = Dir[root.join("mentoring/**/*_controller.rb")].map do |path|
      Pathname(path).relative_path_from(root).to_s.delete_suffix(".rb").camelize.constantize
    end

    assert_operator controllers.size, :>=, 17
    controllers.each do |controller|
      assert_equal gate.sort, controller.authorized_roles.to_a.sort,
                   "#{controller.name} is gated differently from the Mentoring menu"
    end
  end

  test "a Mentor Interface Event holder is offered every page while Event Management On Playa is on" do
    set_on_playa(true)

    expected = []
    MegaMenu.each_item(Menus::MENTORING[:sections]) { |item| expected << item[:title] }

    assert_equal 12, expected.size
    assert_equal expected, titles_for(@holder)
  end

  test "a Mentor Interface Event holder is offered no Mentoring category while the setting is off" do
    set_on_playa(false)

    assert_empty titles_for(@holder)
  end

  private

  def set_on_playa(enabled)
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: enabled.to_s)
  end

  # Menu rules read Current.has_role?, which answers from the roles manager.
  def titles_for(holder)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    category = MegaMenu.categories(person: holder, computed: {}).find { |entry| entry[:title] == "Mentoring" }
    return [] unless category

    titles = []
    MegaMenu.each_item(category[:sections]) { |item| titles << item[:title] }
    titles
  end
end
