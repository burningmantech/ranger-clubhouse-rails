# frozen_string_literal: true

require "application_system_test_case"

# A training's Sessions item claims only its session/ subtree (a String
# active_prefix), so the Capacity sibling wins its own page. The browser
# re-derives the active item after the server (active_links_controller), and
# must still light Sessions on its own page, as menu_item_active? does.
class Training::SidebarActiveItemTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Position.create!(id: Position::TRAINING, title: "Training", type: Position::TYPE_TRAINING, active: true)
    ensure_role(Role::TRAINER, "Trainer")
    @trainer = person(:echelon_ranger)
    grant_role(@trainer, Role::TRAINER)
    sign_in(@trainer)
  end

  test "Sessions is the current item on its own page and not on Capacity" do
    sessions = "a[href='#{training_path("in-person")}']"
    capacity = "a[href='#{training_capacity_path("in-person")}']"

    visit training_path("in-person")
    assert_selector "#{sessions}.active[aria-current='true']"

    visit training_capacity_path("in-person")
    assert_selector "#{capacity}.active[aria-current='true']"
    assert_selector "#{sessions}[aria-current='false']"
  end
end
