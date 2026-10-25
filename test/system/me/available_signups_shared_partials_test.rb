# frozen_string_literal: true

require "application_system_test_case"

# Regression tests verifying shared partials (_overlapping_sign_ups, _slot_additional_info)
# render correctly on the available sign-ups page after the schedule card redesign.
# Uses a past year to bypass signup-permission checks (photo, bpguid, etc.)
class Me::AvailableSignupsSharedPartialsTest < ApplicationSystemTestCase
  LONG_URL = "https://example.com/very-long-url-that-exceeds-seventy-five-characters-so-the-read-more-toggle-appears"

  setup do
    @person = person(:active_ranger)
    @position = positions(:training_lead)
    @past_year = Current.year - 1

    # Grant the person this position so the show page allows access
    PersonPosition.create!(person: @person, position: @position)

    sign_in(@person)
  end

  test "overlap alert renders title and updated copy on available sign-ups" do
    # Create two overlapping slots so the conflict scanner flags them
    slot_a = create_past_year_slot(
      begins_offset: 10.hours,
      duration: 6.hours
    )
    slot_b = create_past_year_slot(
      begins_offset: 10.hours,
      duration: 4.hours
    )

    PersonSlot.create!(person: @person, slot: slot_a)
    PersonSlot.create!(person: @person, slot: slot_b)

    visit me_available_sign_up_position_path(position_id: @position.id, year: @past_year)

    assert_text "Overlapping Shift"
    assert_text "Credit is granted only for the shift you check into."
  end

  test "signed-up overlap shows separate badges not combined phrase" do
    slot_a = create_past_year_slot(
      begins_offset: 10.hours,
      duration: 6.hours
    )
    slot_b = create_past_year_slot(
      begins_offset: 10.hours,
      duration: 4.hours
    )

    PersonSlot.create!(person: @person, slot: slot_a)
    PersonSlot.create!(person: @person, slot: slot_b)

    visit me_available_sign_up_position_path(position_id: @position.id, year: @past_year)

    # Separate badges should be present
    assert_text "Signed up"
    assert_text "Overlapping Shift"

    # Combined phrase should be absent
    assert_no_text "Signed up & Overlapping Shift"
  end

  test "signed-up overlap hides availability and shows callout below shift info" do
    slot_a = create_past_year_slot(
      begins_offset: 10.hours,
      duration: 6.hours
    )
    slot_b = create_past_year_slot(
      begins_offset: 10.hours,
      duration: 4.hours
    )

    PersonSlot.create!(person: @person, slot: slot_a)
    PersonSlot.create!(person: @person, slot: slot_b)

    visit me_available_sign_up_position_path(position_id: @position.id, year: @past_year)

    # Signed-up overlapping cards should not show availability text
    assert_no_text "open spots"
    assert_no_text "spot taken"

    # Callout content should still be present
    assert_text "Credit is granted only for the shift you check into."
    assert_text "Overlaps with:"
  end

  test "details area uses Details label and Show details toggle" do
    slot = create_past_year_slot(
      begins_offset: 20.hours,
      duration: 6.hours,
      url: LONG_URL
    )

    visit me_available_sign_up_position_path(position_id: @position.id, year: @past_year)

    assert_text "Details:"
    toggle_btn = find("button[data-action='click->read-more#toggle']")
    assert_equal "Show Details", toggle_btn.find("[data-read-more-target='label']").text
    assert_equal "false", toggle_btn["aria-expanded"]
  end

  test "read-more toggle expands and collapses on available sign-ups" do
    slot = create_past_year_slot(
      begins_offset: 30.hours,
      duration: 6.hours,
      url: LONG_URL
    )

    visit me_available_sign_up_position_path(position_id: @position.id, year: @past_year)

    toggle_btn = find("button[data-action='click->read-more#toggle']")

    # Expand
    toggle_btn.click
    assert_equal "Hide Details", toggle_btn.find("[data-read-more-target='label']").text
    assert_equal "true", toggle_btn["aria-expanded"]

    # Collapse
    toggle_btn.click
    assert_equal "Show Details", toggle_btn.find("[data-read-more-target='label']").text
    assert_equal "false", toggle_btn["aria-expanded"]
  end

  test "non-signed-up overlapping card does not show overlap callout" do
    # Create an unsigned slot in the viewed position
    unsigned_slot = create_past_year_slot(
      begins_offset: 40.hours,
      duration: 6.hours
    )

    # Create a signup in another held position that overlaps with the unsigned slot
    other_position = positions(:khaki_supervisor)
    base = Time.zone.local(@past_year, 8, 25, 8, 0, 0)
    other_slot = Slot.create!(
      position: other_position,
      begins: base + 42.hours,
      ends: base + 46.hours,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )
    PersonSlot.create!(person: @person, slot: other_slot)

    visit me_available_sign_up_position_path(position_id: @position.id, year: @past_year)

    # The unsigned card should not show overlap callout or overlap badge
    assert_no_text "Credit is granted only for the shift you check into."
    assert_no_text "Overlaps with:"
  end

  private

  # Create a slot in the past year. begins_offset is relative to midnight Jan 1 of past year.
  def create_past_year_slot(begins_offset:, duration:, url: nil)
    base = Time.zone.local(@past_year, 8, 25, 8, 0, 0)  # Aug 25 of past year
    slot_begins = base + begins_offset
    Slot.create!(
      position: @position,
      begins: slot_begins,
      ends: slot_begins + duration,
      max: 10,
      active: true,
      url: url,
      timezone: "America/Los_Angeles"
    )
  end
end
