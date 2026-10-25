# frozen_string_literal: true

require "application_system_test_case"

# Dragging a pod card by its grip into a new place in the line.
#
# A browser is the only seam that reaches this. The controller test posts a
# position and passes; what broke was the drag itself, which never got as far
# as posting one. See the connect/disconnect guards in pod_people_controller.js.
class ShiftOperations::CruiseDirectionDragTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper

  YEAR = 2025

  setup do
    dirt = Position.create!(id: Position::DIRT, title: "Dirt", type: Position::TYPE_FRONTLINE,
                            active: true, cruise_direction: true)
    @slot = create_slot(dirt, begins: Time.zone.local(YEAR, 8, 26, 11, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 26, 17, 0, 0), description: "Dirt shift")
    @first, @second, @third = %w[First Second Third].map { |location| Pod.create_shift_pod!(@slot, location:) }

    admin = person(:auditor_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(admin, Role::ADMIN)
    sign_in(admin)
  end

  test "dragging a pod by its grip to the end of the line moves it there" do
    visit shift_operations_cruise_direction_path(slot_id: @slot.id, year: YEAR)

    grips = all(".cruise-direction-pod-grip", count: 3)
    grips.first.drag_to(grips.last)

    assert_text "Pod order updated."
    assert_equal [@second, @third, @first].map(&:id), Pod.shift_pods_for(@slot).pluck(:id)
  end

  # The member lists are the controller those guards live in, so their own
  # drag is held to the same standard: the drop has to reach the server.
  test "dragging a Ranger by their grip into another pod moves them there" do
    ranger = person(:active_ranger)
    @first.add_person!(ranger)

    visit shift_operations_cruise_direction_path(slot_id: @slot.id, year: YEAR)

    find(".cruise-direction-person-grip").drag_to(find("ul[data-pod-id='#{@third.id}']"))

    assert_text "#{ranger.callsign} moved to Pod 3."
    assert @third.current_members.exists?(person_id: ranger.id)
  end
end
