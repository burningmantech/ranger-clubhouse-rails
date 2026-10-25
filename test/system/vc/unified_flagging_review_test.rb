# frozen_string_literal: true

require "application_system_test_case"

# VC › Unified Flagging in a browser: selecting a line is a Turbo frame visit
# that fills the review pane without a page load, and below lg the pane sits
# under the selected line. Only a browser shows either.
class Vc::UnifiedFlaggingReviewTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include IntakeTestHelper
  include PersonTestFactory

  setup do
    # Carries the full intake history in the fixtures, with a personnel_rank
    # of 4 in the current year that puts them on the page, first: their long
    # history makes the pane far taller than a phone's screen.
    @flagged = person(:prospective_ranger)
    # A VC rank of 3 lists them in the second group, below @flagged.
    @below = create_person("Gravelpit", status: Person::PROSPECTIVE)
    PersonIntake.create!(person_id: @below.id, year: Current.year, vc_rank: Intake::BELOW_AVERAGE)
    @admin = person(:auditor_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)
    Current.person = @admin
    place_in_pipeline(@flagged, Current.year)
    place_in_pipeline(@below, Current.year)
    sign_in(@admin)
  end

  teardown do
    Current.reset
  end

  test "selecting a line fills the pane without a page load" do
    visit vc_unified_flagging_path

    assert_selector "aside.review-pane", text: "Select a name"
    # Survives a frame swap and not a page load.
    page.execute_script("window.stayedOnPage = true")

    find("li#person-#{@flagged.id} a").click

    assert_pane_shows @flagged
    assert_selector "li#person-#{@flagged.id} a[aria-current=true]"
    assert_current_path(/person=#{@flagged.id}/)
    assert page.evaluate_script("window.stayedOnPage"), "the click loaded a page instead of swapping the frame"
  end

  # The pane's Delete is a Turbo method link. It has to be a page visit, so the
  # redirect's "Note was deleted." toast in the layout shows; captured as a
  # submission of the workspace frame around the pane, the toast was lost.
  test "deleting a note from the pane shows its toast" do
    visit vc_unified_flagging_path(person: @flagged.id)

    within "aside.review-pane" do
      first(:link, "Delete").click
    end
    accept_confirm_dialog

    assert_selector ".toast-base", text: "Note deleted."
  end

  test "below lg the pane sits under the selected line" do
    on_a_phone do
      visit vc_unified_flagging_path(person: @flagged.id)

      assert_selector "li#person-#{@flagged.id} aside.review-pane"
    end
  end

  # --- regressions from the 2026-10-14 review ---------------------------------

  # Below lg the open pane sits under its line, so selecting a line further
  # down takes it from above the new line. Before, the new line jumped up by
  # the pane's height, out of view, and the reader lost their place.
  #
  # Chrome's scroll anchoring hides the jump by holding the content in view in
  # place; Safari, on every iPhone, has none. Turned off here to see what an
  # iPhone sees. The lines added after the tapped one keep the page long enough
  # that the browser cannot clamp the scroll back onto it either.
  test "below lg the line tapped stays in view as the pane moves under it" do
    40.times do |index|
      after = create_person(format("Gully%02d", index), status: Person::PROSPECTIVE)
      PersonIntake.create!(person_id: after.id, year: Current.year, vc_rank: Intake::BELOW_AVERAGE)
      place_in_pipeline(after, Current.year)
    end

    on_a_phone do
      visit vc_unified_flagging_path(person: @flagged.id)
      assert_selector "li#person-#{@flagged.id} aside.review-pane"
      page.execute_script("document.querySelector('.drawer-content').style.overflowAnchor = 'none'")

      find("li#person-#{@below.id} a").click

      assert_pane_shows @below
      assert_selector "li#person-#{@below.id} aside.review-pane"
      assert_line_in_view @below
    end
  end

  # Selecting a line swaps only the pane, so the link the reader activated
  # keeps focus and the next Tab goes on down the list. Before, the whole list
  # was re-rendered and focus fell to the page.
  test "a line keeps focus after it opens the pane" do
    visit vc_unified_flagging_path
    wait_for_controller "review-pane", "[data-controller~=review-pane]"

    find("li#person-#{@below.id} a").send_keys(:enter)

    assert_pane_shows @below
    assert_equal "person-#{@below.id}", page.evaluate_script("document.activeElement.closest('li')?.id")
  end

  # Back restores Turbo's snapshot of the page, which keeps no scroll position
  # for the inner element this layout scrolls. The selected line comes back
  # into view, with its mark and its pane. On the SE's screen the page header
  # alone fills the fold, so the first line starts below it.
  test "Back returns to the line selected before" do
    on_a_phone(height: 667) do
      visit vc_unified_flagging_path
      wait_for_controller "review-pane", "[data-controller~=review-pane]"
      assert_not line_in_view?(@flagged), "the first line starts out of view, or this proves nothing"

      select_line @flagged
      select_line @below

      page.go_back

      assert_pane_shows @flagged
      assert_selector "li#person-#{@flagged.id} a[aria-current=true]"
      assert_selector "li#person-#{@below.id} a[aria-current]", count: 0
      assert_line_in_view @flagged
    end
  end

  # The body's active-links controller marks a link current only when its
  # query string matches the address exactly. A hand-typed address without the
  # year does not, and it used to unmark the line the server selected.
  test "a hand-typed address keeps the selected line marked" do
    visit vc_unified_flagging_path(person: @flagged.id)
    wait_for_controller "active-links", "body"

    assert_selector "li#person-#{@flagged.id} a[aria-current=true]"
  end

  private

  def assert_pane_shows(target)
    assert_selector "aside.review-pane turbo-frame#uf-pane [data-review-id='#{target.id}']"
  end

  # Selects a line and waits out the whole visit, not just the pane: Turbo
  # finishes a frame visit that advances the URL with a page visit of its own
  # (turbo:load), and a Back sent before that one ends is cancelled by it. No
  # reader is that quick; a test is.
  def select_line(target)
    page.execute_script("window.loadsSeen = 0; " \
                        "document.addEventListener('turbo:load', () => window.loadsSeen++, { once: true })")
    find("li#person-#{target.id} a").click
    assert_pane_shows target
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "Turbo never finished the visit" unless page.evaluate_script("window.loadsSeen > 0")
    end
  end

  # Inside the visible part of the layout's scrolling element, which is what
  # the reader sees below the navbar. A pixel of slack: a line scrolled flush
  # to the edge sits a fraction of one over it.
  def line_in_view?(target)
    page.evaluate_script(<<~JS)
      (() => {
        const line = document.querySelector("li#person-#{target.id} a").getBoundingClientRect()
        const view = document.querySelector(".drawer-content").getBoundingClientRect()
        return line.top >= view.top - 1 && line.bottom <= view.bottom + 1
      })()
    JS
  end

  def assert_line_in_view(target)
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "#{target.callsign}'s line is out of view" unless line_in_view?(target)
    end
  end
end
