# frozen_string_literal: true

require "application_system_test_case"

class Me::ScheduleSignupsCardTest < ApplicationSystemTestCase
  LONG_URL = "https://example.com/very-long-url-that-exceeds-seventy-five-characters-so-the-read-more-toggle-appears"

  setup do
    @person = person(:active_ranger)
    @position = positions(:training_lead)
    @year = Current.year

    # Create a future slot for upcoming shift tests
    @future_slot = Slot.create!(
      position: @position,
      begins: 2.days.from_now,
      ends: 2.days.from_now + 6.hours,
      max: 10,
      active: true,
      description: "Berlin Camp",
      timezone: "America/Los_Angeles"
    )

    PersonSlot.create!(person: @person, slot: @future_slot)

    sign_in(@person)
  end

  # active_ranger has an unapproved photo and no Online Course, so the schedule
  # now arrives gated behind the blocker warning. These tests are about the
  # cards behind the gate -- open it on arrival. The summary hides itself once
  # the disclosure is open, so its visibility is the "still closed" signal.
  def visit(*)
    super
    first("#schedule-gate > summary", minimum: 0)&.click
  end

  # -- Card structure tests --

  test "card renders position title and location label" do
    visit me_schedule_path(year: @year)

    within("[aria-labelledby='slot-#{@future_slot.id}-title']") do
      assert_text @position.title
      assert_text "Info:"
      assert_text "Berlin Camp"
    end
  end

  test "card renders meta row with time duration and credits" do
    visit me_schedule_path(year: @year)

    within("[aria-labelledby='slot-#{@future_slot.id}-title']") do
      assert_text "6 hours"
      assert_text "No credits"
    end
  end

  test "card shows credits when position has credit configuration" do
    PositionCredit.create!(
      position: @position,
      start_time: 1.week.ago,
      end_time: 1.week.from_now,
      credits_per_hour: 1.0,
      description: "Test credits"
    )

    visit me_schedule_path(year: @year)

    within("[aria-labelledby='slot-#{@future_slot.id}-title']") do
      assert_text "credits"
      assert_no_text "No credits"
    end
  end

  test "card has proper aria-labelledby attribute" do
    visit me_schedule_path(year: @year)

    assert_selector "[aria-labelledby='slot-#{@future_slot.id}-title']"
    assert_selector "#slot-#{@future_slot.id}-title", text: @position.title
  end

  test "hours not counted disclaimer shows for non-count-hours position" do
    non_count_position = Position.create!(
      title: "Non Count Hours Position",
      active: true,
      count_hours: false
    )

    non_count_slot = Slot.create!(
      position: non_count_position,
      begins: 4.days.from_now,
      ends: 4.days.from_now + 6.hours,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )
    PersonSlot.create!(person: @person, slot: non_count_slot)

    visit me_schedule_path(year: @year)

    within("[aria-labelledby='slot-#{non_count_slot.id}-title']") do
      assert_text "not qualify for provisions"
    end
  end

  # -- Action row tests --

  test "card shows remove button for future shift" do
    visit me_schedule_path(year: @year)

    within("[aria-labelledby='slot-#{@future_slot.id}-title']") do
      assert_text "Remove from Schedule"
      assert_no_text "Cannot remove after shift start"
    end
  end

  test "card shows disabled status text for ended shift" do
    past_slot = Slot.create!(
      position: @position,
      begins: 3.days.ago,
      ends: 3.days.ago + 6.hours,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )
    PersonSlot.create!(person: @person, slot: past_slot)

    visit me_schedule_path(year: @year)

    within("[aria-labelledby='slot-#{past_slot.id}-title']") do
      assert_text "Cannot remove after shift start"
      assert_no_text "Remove from Schedule"
    end
  end

  test "card shows disabled status text for started shift" do
    started_slot = Slot.create!(
      position: @position,
      begins: 1.hour.ago,
      ends: 5.hours.from_now,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )
    PersonSlot.create!(person: @person, slot: started_slot)

    visit me_schedule_path(year: @year)

    within("[aria-labelledby='slot-#{started_slot.id}-title']") do
      assert_text "Cannot remove after shift start"
      assert_no_text "Remove from Schedule"
    end
  end

  test "card shows Show Sign-Ups toggle button" do
    visit me_schedule_path(year: @year)

    within("[aria-labelledby='slot-#{@future_slot.id}-title']") do
      assert_selector "button", text: "Show Sign-Ups"
    end
  end

  # -- Overlap alert tests --

  test "overlap alert renders with updated copy" do
    overlapping_slot = Slot.create!(
      position: @position,
      begins: @future_slot.begins,
      ends: @future_slot.begins + 4.hours,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )
    PersonSlot.create!(person: @person, slot: overlapping_slot)

    visit me_schedule_path(year: @year)

    assert_text "Overlapping Shift"
    assert_text "Credit is granted only for the shift you check into."
  end

  # -- Details toggle tests --

  test "details toggle renders Show details initially" do
    slot_with_url = create_slot_with_long_url(begins: 3.days.from_now)

    visit me_schedule_path(year: @year)

    within("[aria-labelledby='slot-#{slot_with_url.id}-title']") do
      assert_text "Details:"
      toggle_btn = find("button[data-action='click->read-more#toggle']")
      assert_equal "Show Details", toggle_btn.find("[data-read-more-target='label']").text
      assert_equal "false", toggle_btn["aria-expanded"]
    end
  end

  test "details toggle transitions to Hide Details and back" do
    slot_with_url = create_slot_with_long_url(begins: 3.days.from_now)

    visit me_schedule_path(year: @year)

    within("[aria-labelledby='slot-#{slot_with_url.id}-title']") do
      toggle_btn = find("button[data-action='click->read-more#toggle']")

      # Click to expand
      toggle_btn.click
      assert_equal "Hide Details", toggle_btn.find("[data-read-more-target='label']").text
      assert_equal "true", toggle_btn["aria-expanded"]

      # Click to collapse
      toggle_btn.click
      assert_equal "Show Details", toggle_btn.find("[data-read-more-target='label']").text
      assert_equal "false", toggle_btn["aria-expanded"]
    end
  end

  # -- Keyboard accessibility tests --
  # These tests verify real tab-key traversal (no direct element focusing).

  test "tab order reaches Show Sign-Ups button in future shift card" do
    visit me_schedule_path(year: @year)
    reset_focus

    # Tab forward until Show Sign-Ups receives focus
    tab_until(message: "Show Sign-Ups button never received focus via Tab") do
      active_text.include?("Show Sign-Ups") && active_tag == "button"
    end

    # Tab forward — Remove From Schedule should be the next focusable element
    page.send_keys(:tab)
    assert_includes active_text, "Remove from Schedule",
      "Expected Remove From Schedule to follow Show Sign-Ups in tab order"
  end

  test "tab order skips non-interactive status text for started shift" do
    started_slot = Slot.create!(
      position: @position,
      begins: 1.hour.ago,
      ends: 5.hours.from_now,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )
    PersonSlot.create!(person: @person, slot: started_slot)

    visit me_schedule_path(year: @year)
    reset_focus

    # Tab forward until Show Sign-Ups in the started card receives focus.
    # The started card appears before the future card in chronological order,
    # so the first Show Sign-Ups encountered belongs to the started card.
    tab_until(message: "Show Sign-Ups button never received focus via Tab") do
      active_text.include?("Show Sign-Ups") && active_tag == "button"
    end

    # Tab forward — should skip the non-interactive status text span
    page.send_keys(:tab)
    assert_not_equal "span", active_tag,
      "Status text span should not receive focus via Tab"
  end

  test "details toggle button is keyboard focusable" do
    slot_with_url = create_slot_with_long_url(begins: 3.days.from_now)

    visit me_schedule_path(year: @year)
    reset_focus

    # Tab forward until the read-more toggle receives focus
    tab_until(message: "Details toggle button never received focus via Tab") do
      active_data_action == "click->read-more#toggle" && active_tag == "button"
    end

    # Activate via Enter key
    page.send_keys(:enter)
    card = find("[aria-labelledby='slot-#{slot_with_url.id}-title']")
    toggle_btn = card.find("button[data-action='click->read-more#toggle']")
    assert_equal "true", toggle_btn["aria-expanded"]
  end

  private

  def create_slot_with_long_url(begins:)
    slot = Slot.create!(
      position: @position,
      begins: begins,
      ends: begins + 6.hours,
      max: 10,
      active: true,
      url: LONG_URL,
      timezone: "America/Los_Angeles"
    )
    PersonSlot.create!(person: @person, slot: slot)
    slot
  end

  # -- Keyboard navigation helpers --

  # Blur, not body.focus(): the body cannot take focus, so that left it on the
  # gate's summary, which hides itself once clicked open -- and a Tab sent to a
  # hidden element is refused as not interactable.
  def reset_focus
    page.execute_script("document.activeElement?.blur()")
  end

  def active_text
    page.evaluate_script("document.activeElement?.textContent?.trim()") || ""
  end

  def active_tag
    page.evaluate_script("document.activeElement?.tagName?.toLowerCase()") || ""
  end

  def active_data_action
    page.evaluate_script("document.activeElement?.getAttribute('data-action')")
  end

  def tab_until(max_tabs: 30, message: "Expected element not found within tab sequence")
    max_tabs.times do
      page.send_keys(:tab)
      return if yield
    end
    flunk "#{message} (tried #{max_tabs} tabs)"
  end
end
