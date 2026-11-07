# frozen_string_literal: true

require "application_system_test_case"

# The phone drawer's header row (SidebarHelper#sidebar_menu): its Close closes
# the drawer. The row sits above the logo pinned at the drawer's bottom, which
# reaches it in a drawer under about 225px tall (heavy zoom) and, before the row
# had a z-index of its own, painted over Close and took the click.
class SidebarDrawerTest < ApplicationSystemTestCase
  setup { sign_in(person(:active_ranger)) }

  test "Close in the drawer's header row closes the drawer" do
    assert_close_closes_the_drawer
  end

  test "Close still closes a drawer short enough for the logo to reach the header row" do
    assert_close_closes_the_drawer(height: 180)
  end

  private

  def assert_close_closes_the_drawer(height: 812)
    on_a_phone(height:) do
      visit me_root_path
      find("#sidebar-toggle").click
      assert_checked_field "sidebar-drawer", visible: :all

      within("#sidebar-drawer-content") { click_button "Close" }
      assert_unchecked_field "sidebar-drawer", visible: :all
    end
  end
end
