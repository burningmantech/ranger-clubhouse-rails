# frozen_string_literal: true

require "test_helper"

class Scheduling::SlotBulkEditsControllerTest < ActionDispatch::IntegrationTest
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

    @first = create_slot(description: "First shift")
    @second = create_slot(description: "Second shift", begins: "2026-08-26 06:45", ends: "2026-08-26 12:00")
    @third = create_slot(description: "Third shift", begins: "2026-08-27 06:45", ends: "2026-08-27 12:00")

    sign_in_as(@editor)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  def create_slot(position: @position, begins: "2026-08-25 06:45", ends: "2026-08-25 12:00", **attrs)
    Slot.create!({ position_id: position.id, begins:, ends:, max: 10,
                   description: "Morning", active: true }.merge(attrs))
  end

  test "denies access without the edit slots role" do
    sign_in_as(@outsider)

    get scheduling_new_slot_bulk_edit_path(@position.id)

    assert_redirected_to me_root_path
  end

  test "new lists every slot checked" do
    get scheduling_new_slot_bulk_edit_path(@position.id)

    assert_response :success
    assert_select "input[name='slot_ids[]'][checked]", count: 3
    assert_select "body", text: /First shift/
  end

  test "unknown position redirects back to the index" do
    get scheduling_new_slot_bulk_edit_path(999_999)

    assert_redirected_to scheduling_slots_path(year: 2026)
  end

  test "applies filled fields to the checked slots only" do
    post scheduling_slot_bulk_edits_path(@position.id, year: 2026), params: {
      description: "Renamed", max: "", url: "",
      slot_ids: [@first.id, @second.id]
    }

    assert_redirected_to scheduling_slots_position_path(@position.id, year: 2026)
    assert_equal "2 slots updated.", flash[:success]
    assert_equal "Renamed", @first.reload.description
    assert_equal "Renamed", @second.reload.description
    assert_equal "Third shift", @third.reload.description
    assert_equal 10, @first.max
  end

  test "moves slots to a new position and redirects there" do
    post scheduling_slot_bulk_edits_path(@position.id, year: 2026), params: {
      new_position_id: @other_position.id,
      slot_ids: [@first.id]
    }

    assert_redirected_to scheduling_slots_position_path(@other_position.id, year: 2026)
    assert_equal @other_position.id, @first.reload.position_id
    assert_equal @position.id, @second.reload.position_id
  end

  test "requires a selection" do
    post scheduling_slot_bulk_edits_path(@position.id, year: 2026),
         params: { description: "Renamed" }

    assert_response :unprocessable_entity
    assert_select "body", text: /Select at least one slot to update/
  end

  # to_i read "#{id}x" as the id and updated that slot.
  test "slot ids that are not ids select nothing" do
    post scheduling_slot_bulk_edits_path(@position.id, year: 2026),
         params: { description: "Renamed", slot_ids: ["", "abc", "#{@first.id}x"] }

    assert_response :unprocessable_entity
    assert_select "body", text: /Select at least one slot to update/
    assert_equal "First shift", @first.reload.description
  end

  test "requires at least one field" do
    post scheduling_slot_bulk_edits_path(@position.id, year: 2026),
         params: { slot_ids: [@first.id] }

    assert_response :unprocessable_entity
    assert_select "body", text: /Fill in at least one field to apply/
  end

  test "filters the listing by status" do
    @second.update!(active: false)

    get scheduling_new_slot_bulk_edit_path(@position.id, filter: { active: "inactive" })

    assert_select "input[name='slot_ids[]']", count: 1
    assert_select "input[name='slot_ids[]'][value=?]", @second.id.to_s
  end

  test "filters the listing by description" do
    get scheduling_new_slot_bulk_edit_path(@position.id, filter: { description: "First shift" })

    assert_select "input[name='slot_ids[]']", count: 1
    assert_select "input[name='slot_ids[]'][value=?]", @first.id.to_s
  end

  test "filters the listing by date" do
    get scheduling_new_slot_bulk_edit_path(@position.id, filter: { date: "2026-08-27" })

    assert_select "input[name='slot_ids[]']", count: 1
    assert_select "input[name='slot_ids[]'][value=?]", @third.id.to_s
  end

  test "filters the listing by time of day across dates" do
    late = create_slot(description: "Late shift", begins: "2026-08-25 18:00", ends: "2026-08-25 22:00")

    get scheduling_new_slot_bulk_edit_path(@position.id, filter: { time: "18:00" })

    assert_select "input[name='slot_ids[]']", count: 1
    assert_select "input[name='slot_ids[]'][value=?]", late.id.to_s
  end

  test "filters the listing by an exact date and time" do
    get scheduling_new_slot_bulk_edit_path(@position.id,
                                           filter: { datetime: @second.begins.iso8601 })

    assert_select "input[name='slot_ids[]']", count: 1
    assert_select "input[name='slot_ids[]'][value=?]", @second.id.to_s
  end

  test "combined filters narrow with AND semantics" do
    get scheduling_new_slot_bulk_edit_path(@position.id,
                                           filter: { description: "First shift", date: "2026-08-27" })

    assert_select "input[name='slot_ids[]']", count: 0
    assert_select "body", text: /No slots match the current filters/
  end

  test "a non-hash filter param is ignored rather than raising" do
    ["filter=x", "filter[]=a&filter[]=b", "filter"].each do |query|
      get "#{scheduling_new_slot_bulk_edit_path(@position.id)}?#{query}"

      assert_response :success
      assert_select "input[name='slot_ids[]']", count: 3
    end
  end

  test "an active filter is carried into the update submit target" do
    get scheduling_new_slot_bulk_edit_path(@position.id, filter: { description: "First shift" })

    assert_select "form[action*='filter%5Bdescription%5D=First+shift']"
  end

  test "only filtered slots are updated when a filter is active" do
    post scheduling_slot_bulk_edits_path(@position.id, year: 2026,
                                         filter: { description: "First shift" }),
         params: { description: "Renamed", slot_ids: [@first.id, @second.id] }

    assert_redirected_to scheduling_slots_position_path(@position.id, year: 2026)
    assert_equal "1 slot updated.", flash[:success]
    assert_equal "Renamed", @first.reload.description
    assert_equal "Second shift", @second.reload.description
  end

  test "a validation failure rolls back every change" do
    post scheduling_slot_bulk_edits_path(@position.id, year: 2026), params: {
      description: "x" * 41,
      slot_ids: [@first.id, @second.id]
    }

    assert_response :unprocessable_entity
    assert_equal "First shift", @first.reload.description
    assert_equal "Second shift", @second.reload.description
  end
end
