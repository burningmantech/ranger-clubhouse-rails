# frozen_string_literal: true

require "test_helper"

class Scheduling::SlotsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include CacheTestHelper
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
    @parent_position = Position.create!(title: "Trainer Cadre", active: true)
    @child_position = Position.create!(title: "Trainee Crew", active: true,
                                       parent_position_id: @parent_position.id)

    sign_in_as(@editor)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  def create_slot(position: @position, begins: "2026-08-25 06:45", ends: "2026-08-25 12:00", **attrs)
    Slot.create!({ position_id: position.id, begins:, ends:, max: 10,
                   description: "Morning", active: false }.merge(attrs))
  end

  test "denies access without the edit slots role" do
    sign_in_as(@outsider)

    get scheduling_slots_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Slots role required to manage slots.", flash[:error]
  end

  test "index groups slots by position with counts and inactive badge" do
    create_slot(active: true)
    create_slot(begins: "2026-08-26 06:45", ends: "2026-08-26 12:00")
    create_slot(position: @other_position, active: true)

    get scheduling_slots_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(@position.title)}/
    assert_select "body", text: /2 slots/
    assert_select "body", text: /1 inactive/
    assert_select "body", text: /#{Regexp.escape(@other_position.title)}/
    assert_select "body", text: /Showing 2 positions with 3 slots/
    # No EventDate record exists for the year.
    assert_select "body", text: /Pre-Event Slot Dates Are Not Set Up/
  end

  test "index shows the pre-event period when event dates exist" do
    create_slot
    EventDate.create!(event_start: "2026-08-30", event_end: "2026-09-07",
                      pre_event_start: "2026-08-15", post_event_end: "2026-09-12",
                      pre_event_slot_start: "2026-08-20 00:00", pre_event_slot_end: "2026-08-29 00:00")

    get scheduling_slots_path

    assert_response :success
    assert_select "body", text: /pre-event period is/
  end

  test "index shows an empty state for a year without slots" do
    get scheduling_slots_path(year: 2024)

    assert_response :success
    assert_select "body", text: /No slots were found for 2024/
  end

  test "position page lists slots with linked slot details" do
    trainer_slot = create_slot(position: @parent_position, description: "Trainer shift", active: true)
    create_slot(position: @child_position, description: "Trainee shift",
                trainer_slot_id: trainer_slot.id, url: "See https://example.com/brief")

    get scheduling_slots_position_path(@child_position.id)

    assert_response :success
    assert_select "body", text: /Trainee shift/
    assert_select "body", text: /Multiplier: ##{trainer_slot.id}/
    assert_select "body", text: /0 of 10/
    # The additional info is collapsed behind a disclosure on this page only.
    assert_select "details > summary", text: "Details"
  end

  test "position page shows parent and child links" do
    parent_slot = create_slot(position: @parent_position, description: "Parent shift")
    child_slot = create_slot(position: @child_position, description: "Child shift",
                             parent_signup_slot_id: parent_slot.id)

    get scheduling_slots_position_path(@child_position.id)
    assert_select "body", text: /Parent: ##{parent_slot.id}/

    get scheduling_slots_position_path(@parent_position.id)
    assert_select "body", text: /Child: ##{child_slot.id}/
  end

  test "unknown position redirects back to the index" do
    get scheduling_slots_position_path(999_999)

    assert_redirected_to scheduling_slots_path(year: 2026)
    assert_equal "The position could not be found.", flash[:error]
  end

  test "creates a slot" do
    assert_difference "Slot.count", 1 do
      post scheduling_slots_path, params: {
        slot: { position_id: @position.id, description: "Sunset", begins: "2026-08-27 18:00",
                ends: "2026-08-28 00:00", timezone: "America/Los_Angeles", max: 5, active: "1" }
      }
    end

    slot = Slot.order(:id).last
    assert_equal 2026, slot.begins_year
    assert slot.active
    assert_redirected_to scheduling_slots_position_path(@position.id, year: 2026, anchor: "slot-#{slot.id}")
    assert_equal "Slot created.", flash[:success]
  end

  test "create failure re-renders the form with errors" do
    assert_no_difference "Slot.count" do
      post scheduling_slots_path, params: {
        slot: { position_id: @position.id, description: "Backwards", begins: "2026-08-27 18:00",
                ends: "2026-08-27 06:00", max: 5 }
      }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /must be before the ending time|before/i
  end

  test "new for a prior year shows a warning callout" do
    get scheduling_new_slot_path(year: 2025)

    assert_response :success
    assert_select "body", text: /Not the Current Year/
  end

  test "new for the current year has no prior year warning" do
    get scheduling_new_slot_path

    assert_response :success
    assert_select "body", { text: /Not the Current Year/, count: 0 }
  end

  test "updates a slot" do
    slot = create_slot

    patch scheduling_slot_path(slot), params: { slot: { description: "Renamed" } }

    assert_redirected_to scheduling_slots_position_path(@position.id, year: 2026, anchor: "slot-#{slot.id}")
    assert_equal "Renamed", slot.reload.description
  end

  test "save as new clones the form values without links and keeps the original" do
    trainer_slot = create_slot(position: @parent_position, description: "Trainer shift")
    slot = create_slot(position: @child_position, description: "Original",
                       trainer_slot_id: trainer_slot.id)

    assert_difference "Slot.count", 1 do
      patch scheduling_slot_path(slot), params: {
        save_as_new: "1",
        slot: { position_id: @child_position.id, description: "Cloned", begins: "2026-08-25 06:45",
                ends: "2026-08-25 12:00", timezone: "America/Los_Angeles", max: 10,
                trainer_slot_id: trainer_slot.id }
      }
    end

    clone = Slot.order(:id).last
    assert_equal "Cloned", clone.description
    assert_nil clone.trainer_slot_id
    assert_equal "Original", slot.reload.description
    assert_redirected_to scheduling_edit_slot_path(clone, year: 2026)
  end

  test "destroys a slot" do
    slot = create_slot

    assert_difference "Slot.count", -1 do
      delete scheduling_slot_path(slot)
    end

    assert_redirected_to scheduling_slots_position_path(@position.id, year: 2026)
  end

  test "position page filters by day, status, and description" do
    morning = create_slot(description: "Morning", active: true)
    sunset = create_slot(begins: "2026-08-26 06:45", ends: "2026-08-26 12:00", description: "Sunset")

    get scheduling_slots_position_path(@position.id, day: "2026-08-25")
    assert_response :success
    assert_select "input[name='slot_ids[]']", count: 1
    assert_select "tr#slot-#{morning.id}"
    assert_select "tr#slot-#{sunset.id}", count: 0
    assert_select "body", text: /Showing 1 of 2 slots/

    get scheduling_slots_position_path(@position.id, active: "inactive")
    assert_select "tr#slot-#{sunset.id}"
    assert_select "tr#slot-#{morning.id}", count: 0

    get scheduling_slots_position_path(@position.id, description: "Sunset")
    assert_select "tr#slot-#{sunset.id}"
    assert_select "tr#slot-#{morning.id}", count: 0
    # The dropdown lists every description for the position, filtered or not.
    assert_select "select[name='description'] option", text: "Morning"
  end

  test "position page shows an empty state when no slots match the filters" do
    create_slot(description: "Morning")

    get scheduling_slots_position_path(@position.id, description: "zzz")

    assert_response :success
    assert_select "body", text: /No slots match the current filters/
  end

  test "bulk delete removes only the selected slots in the position and year" do
    keep = create_slot(description: "Keep")
    first = create_slot(begins: "2026-08-26 06:45", ends: "2026-08-26 12:00")
    second = create_slot(begins: "2026-08-27 06:45", ends: "2026-08-27 12:00")
    other_position_slot = create_slot(position: @other_position)
    prior_year_slot = create_slot(begins: "2025-08-26 06:45", ends: "2025-08-26 12:00")

    assert_difference "Slot.count", -2 do
      delete scheduling_slots_position_bulk_delete_path(@position.id, year: 2026),
             params: { slot_ids: [first.id, second.id, other_position_slot.id, prior_year_slot.id] }
    end

    assert_redirected_to scheduling_slots_position_path(@position.id, year: 2026)
    assert_equal "2 slots deleted.", flash[:success]
    assert Slot.exists?(keep.id)
    assert Slot.exists?(other_position_slot.id)
    assert Slot.exists?(prior_year_slot.id)
  end

  test "bulk delete cascades sign-ups" do
    slot = create_slot
    PersonSlot.create!(person: @editor, slot: slot)

    delete scheduling_slots_position_bulk_delete_path(@position.id, year: 2026),
           params: { slot_ids: [slot.id] }

    assert_equal "1 slot deleted.", flash[:success]
    assert_not Slot.exists?(slot.id)
    assert_not PersonSlot.exists?(slot_id: slot.id)
  end

  test "bulk delete with nothing selected redirects with an error" do
    create_slot

    assert_no_difference "Slot.count" do
      delete scheduling_slots_position_bulk_delete_path(@position.id, year: 2026)
    end

    assert_redirected_to scheduling_slots_position_path(@position.id, year: 2026)
    assert_equal "Select at least one slot to delete.", flash[:error]
  end

  # ActiveRecord reads "#{id}x" as the id, which deleted that slot.
  test "bulk delete with slot ids that are not ids deletes nothing" do
    slot = create_slot

    assert_no_difference "Slot.count" do
      delete scheduling_slots_position_bulk_delete_path(@position.id, year: 2026),
             params: { slot_ids: ["", "abc", "#{slot.id}x"] }
    end

    assert_equal "Select at least one slot to delete.", flash[:error]
  end

  test "repeat duplicates a slot without links" do
    trainer_slot = create_slot(position: @parent_position)
    slot = create_slot(position: @child_position, trainer_slot_id: trainer_slot.id)

    assert_difference "Slot.count", 1 do
      post scheduling_repeat_slot_path(slot)
    end

    copy = Slot.order(:id).last
    assert_equal slot.begins, copy.begins
    assert_equal slot.description, copy.description
    assert_nil copy.trainer_slot_id
    assert_equal "The slot has been repeated.", flash[:success]
  end

  test "repeat with add24 shifts the times by a day" do
    slot = create_slot

    post scheduling_repeat_slot_path(slot, add24: 1)

    copy = Slot.order(:id).last
    assert_equal slot.begins + 24.hours, copy.begins
    assert_equal slot.ends + 24.hours, copy.ends
    assert_equal "The slot has been repeated with a 24 hour addition.", flash[:success]
  end

  test "set active all only touches the position and year" do
    first = create_slot
    second = create_slot(begins: "2026-08-26 06:45", ends: "2026-08-26 12:00")
    other_position_slot = create_slot(position: @other_position)
    prior_year_slot = create_slot(begins: "2025-08-26 06:45", ends: "2025-08-26 12:00")

    post scheduling_slots_position_active_path(@position.id, active: 1, year: 2026)

    assert_redirected_to scheduling_slots_position_path(@position.id, year: 2026)
    assert_equal "2 slots activated.", flash[:success]
    assert first.reload.active
    assert second.reload.active
    assert_not other_position_slot.reload.active
    assert_not prior_year_slot.reload.active

    post scheduling_slots_position_active_path(@position.id, active: 0, year: 2026)
    assert_equal "2 slots deactivated.", flash[:success]
    assert_not first.reload.active
  end

  # update_all skips Slot's callbacks, and an active trainer's slot is what
  # counts as teaching, so the action purges the trainers' role sets itself.
  test "set active all purges the role sets of the trainers on those slots" do
    position = positions(:non_eligible_position)
    slot = create_slot(position:, active: true)
    trainer = person(:echelon_ranger)
    TrainerStatus.create!(person_id: trainer.id, slot_id: slot.id, trainer_slot_id: slot.id,
                          status: TrainerStatus::STATUS_ATTENDED)

    with_cache_store do |cache|
      RoleManager.retrieve(trainer)
      key = RoleManager.cache_key(trainer.id)
      assert cache.exist?(key), "RoleManager did not cache the role set; test cannot prove invalidation"

      post scheduling_slots_position_active_path(position.id, active: 0, year: 2026)

      assert_equal "1 slot deactivated.", flash[:success]
      assert_not cache.exist?(key), "switching the slots off left a stale role set cached"
    end
  end

  test "link options renders choices for a child position" do
    trainer_slot = create_slot(position: @parent_position, description: "Trainer shift")

    get scheduling_slots_link_options_path(position_id: @child_position.id, year: 2026)

    assert_response :success
    assert_select "turbo-frame#slot-link-options"
    assert_select "option", text: /Trainer shift/
  end

  test "link options explains when the position is not a child position" do
    get scheduling_slots_link_options_path(position_id: @position.id, year: 2026)

    assert_response :success
    assert_select "body", text: /not a child position/
  end
end
