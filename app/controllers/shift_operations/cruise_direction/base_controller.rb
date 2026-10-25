# frozen_string_literal: true

# Shared gate, shift lookup, and stream plumbing for Cruise Direction.
#
# Upstream's PodPolicy lets four roles at pods: Admin, Pod Management, and
# Mentor may write, Event Management may read. Only the first two are carried
# over, matching the gate on upstream's own page -- the mentor cadre manages
# Alpha pods through the Alpha Pod Management interface, and a read-only role
# has nothing to do on a page that is entirely controls.
class ShiftOperations::CruiseDirection::BaseController < ApplicationController
  layout "shift_operations"

  before_action :setup_year

  # `load_slot` and `load_pod` are registered by each subclass rather than
  # here: Rails raises when an `except:` list names an action a controller does
  # not define, and only the page controller has the shiftless first view.

  authorize_role [Role::ADMIN, Role::POD_MANAGEMENT],
                 message: "Admin or Pod Management role required to manage Cruise Direction pods."

  # `params.expect` raises before any action's own rescue can see it, and a
  # bare 400 is the one answer on this page that carries neither a stream nor a
  # toast: the dialog would sit there unchanged with nothing said.
  rescue_from ActionController::ParameterMissing do
    render_refusal("That request arrived without the pod's details. Try again.")
  end

  # The pod tables hold nothing before 2023, matching upstream's YearSelect.
  self.year_floor = 2023

  private

  # The shift being managed, from the picker's query parameter.
  #
  # Scoped exactly as the picker's own list is -- Slot.retrieve_dirt_times
  # filters on the year and on `active` as well as the dirt positions. Anything
  # looser lets a write land on a shift this page can never select again: the
  # pod would exist, hold a place in that shift's 1..N line, and be unreachable
  # from every URL the app hands back.
  def load_slot
    @slot = selectable_shifts.find_by(id: params[:slot_id])
    return if @slot

    render_refusal("That shift is not a dirt shift of #{@year}. Pick a shift from the list.")
  end

  # For everything done to an existing pod, the shift comes off the pod itself.
  # One id in the URL instead of two that could disagree.
  #
  # The pod's own shift is then held to the same rule as a picked one. `pod` is
  # written by the Laravel side too, so "no shift pod sits off a dirt shift" is
  # an assumption about the other application rather than something this one
  # enforces -- and one such row would otherwise open the whole mutation
  # surface on a shift the picker refuses to offer.
  def load_pod
    @pod = Pod.of_type(Pod::TYPE_SHIFT).find_by(id: params[:id] || params[:pod_id])
    return render_refusal("That pod is no longer on this shift.") unless @pod

    @slot = selectable_shifts.find_by(id: @pod.slot_id)
    render_refusal("That pod's shift is no longer one this page manages.") unless @slot
  end

  def selectable_shifts
    Slot.active.for_year(@year).where(position_id: CruiseDirectionBoard::DIRT_POSITIONS)
  end

  def board_path = shift_operations_cruise_direction_path(slot_id: @slot&.id, year: @year)

  def pod_name(pod) = helpers.cruise_direction_pod_name(pod)

  # Every mutation re-renders the whole board. Adding someone renumbers a pod,
  # moving someone touches two of them, and a drag renumbers the line, so a
  # per-card stream would be a stream per card in most cases anyway.
  #
  # A nil message redraws without saying anything, for a write that turned out
  # to change nothing -- a card dropped back where it started still needs the
  # board re-rendered, and does not need a toast about it.
  def render_board(message = nil, type = :success)
    board = CruiseDirectionBoard.for_slot(@slot)

    respond_to do |format|
      format.turbo_stream do
        streams = [*board_stream(board), modal_close_dialog]
        streams << ui_toast_stream(message, type) if message

        render turbo_stream: streams
      end
      format.html { redirect_to board_path, flash: message ? { type => message } : {} }
    end
  end

  # The one place the board's stream targets and partials are named. Every write
  # answers with the whole board, and `pods#create` needs the same streams
  # beside a dialog rather than beside a close.
  #
  # Two targets, not one: the shift's counts render beside the picker in the
  # page shell, so they cannot ride along inside the cards partial. Splat this.
  def board_stream(board)
    [
      turbo_stream.replace("cruise-direction-board", partial: "shift_operations/cruise_direction/board",
                                                     locals: { board:, year: @year }),
      turbo_stream.replace("cruise-direction-stats", partial: "shift_operations/cruise_direction/stats",
                                                     locals: { board: })
    ]
  end

  # The add dialog's two lists, split out of a board already in hand. Asking
  # CruiseDirectionBoard.pools_for would re-run the whole candidate pipeline --
  # five statements -- for the same rows the board is carrying as `unassigned`.
  def pools_from(board) = CruiseDirectionBoard.pools_from(board.unassigned, board.slot)

  # A request that could not be honoured: the board is unchanged, so only the
  # dialog and the toast need saying.
  #
  # Three answers, because three kinds of request reach here. A write accepts
  # turbo streams. A dialog OPEN does not -- Turbo only asks for a stream on
  # non-safe requests, so a frame GET whose guard fails would otherwise be
  # redirected and Turbo would quietly swap in the layout's empty "modal"
  # frame, showing the reader nothing at all. That one gets the message
  # rendered into the frame instead. Anything else is a plain navigation.
  def render_refusal(message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [modal_close_dialog, ui_toast_stream(message, :error)],
               status: :unprocessable_entity
      end
      format.html do
        if turbo_frame_request?
          render "shift_operations/cruise_direction/unavailable", locals: { message: },
                 status: :unprocessable_entity
        else
          redirect_to board_path, error: message
        end
      end
    end
  end
end
