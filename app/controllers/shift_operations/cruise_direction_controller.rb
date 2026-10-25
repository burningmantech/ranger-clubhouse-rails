# frozen_string_literal: true

# Cruise Direction: the pods deployed on one dirt shift.
#
# The page opens on whichever shift is running right now, so an operator who
# lands here mid-event is already looking at the right board. Everything the
# page changes lives in the board partial and is streamed back by the two
# controllers next door.
#
# Upstream: Ember ops/cruise-direction.
class ShiftOperations::CruiseDirectionController < ShiftOperations::CruiseDirection::BaseController
  def index
    @shifts = CruiseDirectionBoard.shifts_for_year(@year)
    @slot = selected_slot
    @board = CruiseDirectionBoard.for_slot(@slot) if @slot
    @positions = CruiseDirectionBoard.positions
  end

  private

  # The shift picked from the list, or -- on the first view -- the one running
  # right now. Resolved against the year's dirt shifts, so a slot id left over
  # from another year or another kind of shift cannot select anything.
  def selected_slot
    shift =
      if params[:slot_id].present?
        @shifts.find { |dirt_shift| dirt_shift.id == params[:slot_id].to_i }
      else
        CruiseDirectionBoard.suggested_shift(@shifts)
      end

    Slot.find_by(id: shift.id) if shift
  end
end
