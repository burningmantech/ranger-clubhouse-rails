# frozen_string_literal: true

require "application_system_test_case"

# The scroll-to-top marker (scroll_to_top_controller) on a results page
# rendered at 422 from a POST, here Bulk Lookup's. Turbo morphs a form
# submission's render into the page, which keeps the element the layout
# scrolls -- .drawer-content; the window never scrolls -- and its place, so
# the reader stayed at the submit button.
class ScrollToTopTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    @admin = person(:active_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)
  end

  test "a results page rendered at 422 opens at its top, after a full load and after a visit" do
    sign_in(@admin)
    on_a_phone(height: 640) do
      visit people_bulk_lookup_path
      look_up_from_the_foot

      page.execute_script("Turbo.visit(#{people_bulk_lookup_path.to_json})")
      assert_no_selector "#found-section"
      look_up_from_the_foot
    end
  end

  private

  def look_up_from_the_foot
    fill_in "Callsigns or Email Addresses", with: "TestRanger"
    page.execute_script("const page = document.querySelector('.drawer-content'); page.scrollTop = page.scrollHeight")
    assert_operator drawer_scroll_top, :>, 0
    click_on "Look Up"
    assert_selector "#found-section", text: "TestRanger"
    assert_eventually("the results opened where the submit button was") { drawer_scroll_top.zero? }
  end

  def drawer_scroll_top = page.evaluate_script("document.querySelector('.drawer-content').scrollTop")
end
