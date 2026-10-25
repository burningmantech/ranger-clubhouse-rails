# frozen_string_literal: true

# Creating, deleting, and reordering the pods of one Alpha shift.
#
# A pod is never created or deleted alone: the mentor, mitten, and alpha rows
# are one trio joined by mentor_pod_id, and the Alpha Mentors Assignment page
# reads them that way. Pod#create_alpha_set! and Pod#destroy_set! own that
# invariant so no route can write half a trio.
class Mentoring::AlphaPods::PodsController < Mentoring::AlphaPods::BaseController
  before_action :load_slot
  before_action :load_mentor_pod, only: [:destroy, :move]

  def create
    Pod.create_alpha_set!(@slot)
    render_board("Pod added.")
  end

  def destroy
    number = @mentor_pod.sort_index
    @mentor_pod.destroy_set!
    render_board("Pod #{number} was deleted.")
  end

  def move
    direction = params[:direction].to_s
    return render_refusal("That is not a direction a pod can move.") unless Pod::MOVE_DIRECTIONS.include?(direction)

    # A pod already at the end of the walk order simply does not move; that is
    # not a failure worth a red toast.
    unless @mentor_pod.move!(direction)
      return render_board("Pod #{@mentor_pod.sort_index} is already #{direction == Pod::MOVE_EARLIER ? "first" : "last"}.", :info)
    end

    render_board("Pod order updated.")
  end

  private

  # Always a mentor pod: it is the one carrying the number, and its trio
  # follows it.
  def load_mentor_pod
    @mentor_pod = Pod.for_slot(@slot).of_type(Pod::TYPE_MENTOR).find_by(id: params[:id])
    return if @mentor_pod

    render_refusal("That pod is no longer on this shift.")
  end
end
