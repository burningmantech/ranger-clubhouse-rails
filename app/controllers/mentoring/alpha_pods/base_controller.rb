# frozen_string_literal: true

# Shared gate, slot lookup, and stream plumbing for Alpha Pod Management.
#
# Upstream's PodPolicy also lets the Pod Management and Event Management roles
# in (write and read respectively). Neither is carried over: this page is the
# mentor cadre's, matching the six sibling /mentoring pages, and Pod
# Management holders reach pods through the Cruise Direction interface.
class Mentoring::AlphaPods::BaseController < ApplicationController
  layout "mentoring"

  before_action :setup_year

  # `load_slot` is registered by each subclass, not here: Rails raises when an
  # `except:` list names an action the controller does not define, and only
  # the page controller has the slotless index to exclude.

  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to manage Alpha pods."

  # The pod tables hold nothing before 2023, matching upstream's YearSelect.
  self.year_floor = 2023

  private

  # Looked up across every year on purpose, so a bookmarked shift keeps
  # meaning the same shift whatever the selector last showed. Restricted to
  # the Alpha position -- pods for any other kind of shift belong to the
  # Cruise Direction interface, not this page.
  def load_slot
    @slot = Slot.for_position(Position::ALPHA).find_by(id: params[:slot_id])
    return if @slot

    redirect_to mentoring_alpha_pods_path(year: @year),
                error: "That shift is not an Alpha shift. Pick a shift from the list."
  end

  def shift_path = mentoring_alpha_pods_shift_path(@slot)

  # Every mutation re-renders the whole board. The alternative -- streaming
  # just the touched card -- breaks the moment a write renumbers the pods or
  # moves someone between two of them, which most of them do; and a board is
  # a handful of cards, not a table of thousands.
  def render_board(message, type = :success)
    @board = AlphaPodBoard.for_slot(@slot)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("alpha-pods-board", partial: "mentoring/alpha_pods/board",
                                                   locals: { board: @board, slot: @slot }),
          modal_close_dialog,
          ui_toast_stream(message, type)
        ]
      end
      format.html { redirect_to shift_path, type => message }
    end
  end

  # A request that could not be honoured: the board is unchanged, so only the
  # dialog and the toast need saying.
  #
  # Three answers, because three kinds of request reach here. A write accepts
  # turbo streams. A dialog OPEN does not -- Turbo only asks for a stream on
  # non-safe requests, so a frame GET whose guard fails would otherwise be
  # redirected, and Turbo would quietly swap the layout's empty "modal" frame
  # in and show the reader nothing at all. That one gets the message rendered
  # into the frame instead. Anything else is a plain browser navigation.
  def render_refusal(message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [modal_close_dialog, ui_toast_stream(message, :error)],
               status: :unprocessable_entity
      end
      format.html do
        if turbo_frame_request?
          render "mentoring/alpha_pods/unavailable", locals: { message: },
                 status: :unprocessable_entity
        else
          redirect_to shift_path, error: message
        end
      end
    end
  end
end
