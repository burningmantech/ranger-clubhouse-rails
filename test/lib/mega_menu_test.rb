# frozen_string_literal: true

require "test_helper"

# MegaMenu.linkable? decides what can be starred and tracked: pages of this
# app only, never actions or URLs elsewhere. MegaMenu.offered? decides who
# gets the menu at all.
class MegaMenuTest < ActiveSupport::TestCase
  include MegaMenuTestHelper

  test "route helpers and app-relative paths are linkable" do
    assert MegaMenu.linkable?({ path: :me_profile_path })
    assert MegaMenu.linkable?({ path: "/training/in-person/capacity" })
  end

  test "other URLs, category keys and actions are not" do
    ["https://example.com", "//example.com", "/\\example.com", "category:account"].each do |path|
      assert_not MegaMenu.linkable?({ path: }), "#{path} must not be linkable"
    end
    assert_not MegaMenu.linkable?({ path: "/x", confirm: "Sure?" })
    assert_not MegaMenu.linkable?({ path: "/x", data: { turbo_method: :post } })
  end

  # The navbar's Menu button, dialog and hotkey go to a person who can see
  # some category beyond My Clubhouse and Account, the two the sidebar and
  # the user dropdown already hold.
  test "a Ranger with no roles sees only My Clubhouse and Account, and is not offered the menu" do
    assert_not offered_to(person(:active_ranger))
  end

  test "any other visible category offers the menu" do
    ranger = person(:active_ranger)
    offer_mega_menu_to(ranger)

    assert offered_to(ranger)
  end

  # The request-time training categories count too. An ART interface role
  # unlocks nothing in the static menus, so the training category is all that
  # person has beyond the two.
  test "a training category alone offers the menu" do
    Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                     type: Position::TYPE_TRAINING, active: true)
    role = Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING
    ensure_role(role, "Green Dot Interface")
    ranger = person(:active_ranger)
    grant_role(ranger, role)

    assert offered_to(ranger)
  end

  # The premise of offered?: My Clubhouse is the /me sidebar, section for
  # section, so a person offered nothing else loses no link with the menu.
  test "My Clubhouse holds exactly the sidebar's sections" do
    assert_equal Menus::ME[:sections].to_set, Menus::MY_CLUBHOUSE[:sections].to_set
  end

  private

  # Menu role rules read Current.has_role?, which answers from the roles
  # manager, not from Current.person (test/lib/admin_menu_test.rb).
  def offered_to(holder)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    MegaMenu.offered?(person: holder, computed: {})
  end
end
