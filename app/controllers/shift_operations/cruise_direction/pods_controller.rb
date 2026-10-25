# frozen_string_literal: true

# Making, changing, ordering, and deleting the pods of one dirt shift.
#
# A shift pod stands alone -- unlike an Alpha pod, which is a trio of linked
# rows -- so these are ordinary writes against one record. What is not ordinary
# is the numbering: pods are called by their place in the line over the radio,
# so a create, a delete, and a drag all have to leave that line 1..N. Pod owns
# that, and every action here goes through it.
class ShiftOperations::CruiseDirection::PodsController < ShiftOperations::CruiseDirection::BaseController
  before_action :load_slot, only: [:new, :create]
  before_action :load_pod, only: [:edit, :update, :destroy, :position]

  # The create dialog. A GET, so it opens into the layout's modal frame.
  def new
    @pod = Pod.new(type: Pod::TYPE_SHIFT, slot_id: @slot.id)
  end

  # A pod is made in order to put Rangers in it, so the add dialog opens on the
  # spot rather than sending the reader back to press Add on the new card.
  # Upstream does the same. The board is replaced underneath it.
  def create
    pod = Pod.create_shift_pod!(@slot, pod_params)
    board = CruiseDirectionBoard.for_slot(@slot)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          *board_stream(board),
          turbo_stream.update("modal", partial: "shift_operations/cruise_direction/people/dialog",
                                       locals: { pod:, pools: pools_from(board), year: @year, frame: false }),
          ui_toast_stream("#{pod_name(pod)} is out. Add the Rangers going out in it.", :success)
        ]
      end
      # The picker ships a noscript submit, so this page does not assume Turbo.
      # Without this branch a create arriving outside it is answered with a
      # turbo-stream document the browser renders as markup or downloads --
      # while the same request FAILING validation redirects properly.
      format.html { redirect_to board_path, success: "#{pod_name(pod)} is out." }
    end
  rescue ActiveRecord::RecordInvalid => e
    render_refusal(e.record.errors.full_messages.join(" "))
  end

  # The change dialog. Where the pod sits in the line comes with it, so the
  # move buttons know which of them would run off an end -- and so the place
  # they post is the place `move_to!` reads.
  def edit = load_line_position

  def update
    @pod.update!(pod_params)
    render_board("#{pod_name(@pod)} updated.")
  rescue ActiveRecord::RecordInvalid => e
    render_refusal(e.record.errors.full_messages.join(" "))
  end

  def destroy
    name = pod_name(@pod)
    @pod.destroy_and_renumber!
    render_board("#{name} was deleted.")
  end

  # Where a dragged card was let go, 1-based, from SortableJS.
  #
  # The board is re-rendered whether or not the pod moved. A drag that changed
  # nothing on the server may still have moved the card on screen -- the
  # browser's idea of the order can be a few seconds stale -- and re-rendering
  # is what puts the numbers back in agreement with the database.
  def position
    moved = @pod.move_to!(params[:position])
    return render_board(moved ? "Pod order updated." : nil) unless from_dialog?

    # The same move made from the dialog's buttons, which are the keyboard path
    # to the drag. `render_board` closes the modal, so going through it would
    # shut the dialog on every press and make moving a pod several places a
    # matter of reopening it each time. The dialog is redrawn in place instead,
    # with the position it now holds.
    load_line_position
    render turbo_stream: [
      *board_stream(CruiseDirectionBoard.for_slot(@slot)),
      turbo_stream.update("modal", partial: "shift_operations/cruise_direction/pods/dialog",
                                   locals: { pod: @pod, position: @position, pod_count: @pod_count,
                                             year: @year, frame: false }),
      *(ui_toast_stream("#{pod_name(@pod)} is now #{@position} of #{@pod_count}.", :success) if moved)
    ]
  end

  private

  # Counted along the line rather than read off sort_index: the two agree only
  # while a line runs exactly 1..N, and `pod` is a Laravel-shared table where
  # gaps and repeats both occur. `move_to!` reads a place in the line, so a
  # place in the line is what the buttons have to post.
  def load_line_position
    line = Pod.shift_pods_for(@slot).pluck(:id)
    @pod_count = line.size
    @position = line.index(@pod.id).to_i + 1
  end

  def from_dialog? = params[:from] == "dialog"

  def pod_params = params.expect(pod: [:transport, :location])
end
