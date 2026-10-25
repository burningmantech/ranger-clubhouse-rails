# frozen_string_literal: true

require "test_helper"

class Scheduling::SlotCopiesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 7, 1, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @editor = person(:active_ranger)
    @outsider = person(:echelon_ranger)

    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    ensure_role(Role::MENTOR, "Mentor")
    grant_role(@editor, Role::EDIT_SLOTS)
    grant_role(@outsider, Role::MENTOR)

    @position = positions(:training_lead)
    @other_position = positions(:ood_position)

    @dawn_slot = create_slot(description: "Dawn patrol", url: "Meet at Tokyo",
                             begins: "2025-08-26 06:00", ends: "2025-08-26 12:00")
    @dusk_slot = create_slot(description: "Dusk patrol",
                             begins: "2025-08-26 18:00", ends: "2025-08-27 00:00")
    @other_slot = create_slot(position: @other_position, description: "OOD overnight",
                              begins: "2025-08-27 00:00", ends: "2025-08-27 06:00")
    @training_slot = create_slot(description: "Training session", training_id: 99)
    @linked_slot = create_slot(description: "Linked mentee", trainer_slot_id: @dawn_slot.id)

    sign_in_as(@editor)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  def create_slot(position: @position, begins: "2025-08-25 06:45", ends: "2025-08-25 12:00", **attrs)
    Slot.create!({ position_id: position.id, begins:, ends:, max: 10,
                   description: "Morning", active: true }.merge(attrs))
  end

  test "denies access without the edit slots role" do
    sign_in_as(@outsider)

    get scheduling_new_slot_copy_path(year: 2025)

    assert_redirected_to me_root_path
  end

  test "new shows labor day defaults and only eligible slots" do
    get scheduling_new_slot_copy_path(year: 2025)

    assert_response :success
    assert_select "body", text: /Labor Day of 2025 is September 1/
    assert_select "body", text: /Labor Day of 2026 is September 7/
    # Labor Day 2025-09-01 -> 2026-09-07 is 371 days.
    assert_select "input[name=delta_days][value='371']"
    assert_select "body", text: /Dawn patrol/
    assert_select "body", text: /OOD overnight/
    assert_select "body", { text: /Training session/, count: 0 }
    assert_select "body", { text: /Linked mentee/, count: 0 }
  end

  test "new with a position restricts the listing to that position" do
    get scheduling_new_slot_copy_path(year: 2025, position_id: @position.id)

    assert_response :success
    assert_select "body", text: /Dawn patrol/
    assert_select "body", { text: /OOD overnight/, count: 0 }
  end

  test "new for the current year shows a warning" do
    get scheduling_new_slot_copy_path(year: 2026)

    assert_response :success
    assert_select "body", text: /Copying from the Current Year/
  end

  test "filters the listing by description" do
    get scheduling_new_slot_copy_path(year: 2025, position_id: @position.id,
                                      filter: { description: "Dawn patrol" })

    assert_response :success
    assert_select "body", text: /Dawn patrol/
    assert_select "body", { text: /Dusk patrol/, count: 0 }
    assert_select "body", text: /Showing 1 of 2 slots/
  end

  test "filters the listing by date" do
    get scheduling_new_slot_copy_path(year: 2025, position_id: @other_position.id,
                                      filter: { date: "2025-08-27" })

    assert_response :success
    assert_select "body", text: /OOD overnight/
  end

  test "filters the listing by time of day across dates" do
    # Dawn (06:00) and dusk (18:00) share a date; only dawn matches 06:00.
    get scheduling_new_slot_copy_path(year: 2025, position_id: @position.id,
                                      filter: { time: "06:00" })

    assert_response :success
    assert_select "body", text: /Dawn patrol/
    assert_select "body", { text: /Dusk patrol/, count: 0 }
  end

  test "filters the listing by an exact date and time" do
    get scheduling_new_slot_copy_path(year: 2025, position_id: @position.id,
                                      filter: { datetime: @dusk_slot.begins.iso8601 })

    assert_response :success
    assert_select "body", text: /Dusk patrol/
    assert_select "body", { text: /Dawn patrol/, count: 0 }
  end

  test "combined filters narrow with AND semantics" do
    get scheduling_new_slot_copy_path(year: 2025, position_id: @position.id,
                                      filter: { description: "Dawn patrol", time: "18:00" })

    assert_response :success
    assert_select "body", text: /No slots match the current filters/
  end

  test "a non-hash filter param is ignored rather than raising" do
    ["filter=x", "filter[]=a&filter[]=b", "filter"].each do |query|
      get "#{scheduling_new_slot_copy_path(year: 2025, position_id: @position.id)}&#{query}"

      assert_response :success
      assert_select "input[name='slot_ids[]']", count: 2
    end
  end

  test "an active filter is carried into the copy submit target" do
    get scheduling_new_slot_copy_path(year: 2025, position_id: @position.id,
                                      filter: { time: "06:00" })

    assert_response :success
    assert_select "form[action*='filter%5Btime%5D=06%3A00']"
  end

  test "copies the selected slots with shifted times" do
    assert_difference "Slot.count", 2 do
      post scheduling_slot_copies_path(year: 2025), params: {
        slot_ids: [@dawn_slot.id, @other_slot.id],
        delta_days: 371, delta_hours: 1, delta_minutes: 30,
        activate: "1"
      }
    end

    assert_redirected_to scheduling_slots_path(year: 2025)
    assert_equal "2 slots copied.", flash[:success]

    copy = Slot.for_year(2026).for_position(@position.id).first
    assert_equal @dawn_slot.begins + 371.days + 1.hour + 30.minutes, copy.begins
    assert_equal @dawn_slot.ends + 371.days + 1.hour + 30.minutes, copy.ends
    assert_equal "Dawn patrol", copy.description
    assert_equal "Meet at Tokyo", copy.url
    assert_equal 10, copy.max
    assert copy.active
    assert_nil copy.trainer_slot_id
    assert_equal 2026, copy.begins_year
    assert_equal 1, Slot.for_year(2026).for_position(@other_position.id).count
  end

  test "copies apply attribute overrides and a new position" do
    assert_difference "Slot.count", 1 do
      post scheduling_slot_copies_path(year: 2025), params: {
        slot_ids: [@dawn_slot.id],
        delta_days: 371, delta_hours: 0, delta_minutes: 0,
        new_position_id: @other_position.id,
        description: "Overridden", max: 4
      }
    end

    copy = Slot.for_year(2026).order(:id).last
    assert_equal @other_position.id, copy.position_id
    assert_equal "Overridden", copy.description
    assert_equal 4, copy.max
    assert_not copy.active
  end

  test "cannot copy multiple positions into a single position" do
    assert_no_difference "Slot.count" do
      post scheduling_slot_copies_path(year: 2025), params: {
        slot_ids: [@dawn_slot.id, @other_slot.id],
        delta_days: 371, delta_hours: 0, delta_minutes: 0,
        new_position_id: @other_position.id
      }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /Multiple positions cannot be copied into a single position/
  end

  test "copy with nothing selected fails" do
    assert_no_difference "Slot.count" do
      post scheduling_slot_copies_path(year: 2025),
           params: { delta_days: 371, delta_hours: 0, delta_minutes: 0 }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /Select at least one slot to copy/
  end

  # to_i read "#{id}x" as the id and copied that slot.
  test "slot ids that are not ids copy nothing" do
    assert_no_difference "Slot.count" do
      post scheduling_slot_copies_path(year: 2025),
           params: { delta_days: 371, delta_hours: 0, delta_minutes: 0,
                     slot_ids: ["", "abc", "#{@dawn_slot.id}x"] }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /Select at least one slot to copy/
  end

  test "ineligible slots are ignored even when submitted" do
    assert_no_difference "Slot.count" do
      post scheduling_slot_copies_path(year: 2025), params: {
        slot_ids: [@training_slot.id, @linked_slot.id],
        delta_days: 371, delta_hours: 0, delta_minutes: 0
      }
    end

    assert_response :unprocessable_entity
  end

  test "preview re-renders the form without copying" do
    assert_no_difference "Slot.count" do
      post scheduling_slot_copies_path(year: 2025), params: {
        preview: "Update Preview",
        slot_ids: [@dawn_slot.id],
        delta_days: 10, delta_hours: 0, delta_minutes: 0
      }
    end

    assert_response :unprocessable_entity
    assert_select "input[name=delta_days][value='10']"
    assert_select "input#copy-slot-#{@dawn_slot.id}[checked]"
    # 2025-08-26 06:00 + 10 days
    assert_select "body", text: /Sep 5, 2025 @ 06:00/
  end
end
