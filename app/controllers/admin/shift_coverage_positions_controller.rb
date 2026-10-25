# frozen_string_literal: true

# The posts of one shift type: the columns its report shows. A post is always
# reached through its shift type, which is what stops another shift type's post
# from being edited from this one's page.
class Admin::ShiftCoveragePositionsController < Admin::ShiftCoverageBaseController
  before_action :set_group
  before_action :set_post, only: [:edit, :update, :destroy, :move]

  def new
    @post = @group.shift_coverage_positions.new
  end

  def create
    @post = @group.shift_coverage_positions.new(post_params)
    # A new post joins the end of its shift type; moving it is a separate step.
    @post.sort_index = @post.next_sort_index

    return render(:new, status: :unprocessable_entity) unless @post.save

    redirect_to admin_shift_coverage_group_path(@group), success: "Post created."
  end

  def edit
  end

  def update
    return render(:edit, status: :unprocessable_entity) unless @post.update(post_params)

    redirect_to admin_shift_coverage_group_path(@group), success: "Post updated."
  end

  def destroy
    @post.destroy!

    redirect_to admin_shift_coverage_group_path(@group), success: "\"#{@post.title}\" deleted."
  end

  def move
    move_in_line(@post, admin_shift_coverage_group_path(@group), "The post order has been updated.",
                 "\"#{@post.title}\" is already at that end.")
  end

  private

  def set_group
    @group = ShiftCoverageGroup.find(params.expect!(:shift_coverage_group_id))
  end

  # Through the shift type, so another shift type's post answers 404.
  def set_post
    @post = @group.shift_coverage_positions.find(params.expect!(:id))
  end

  # The position rows arrive as two lists side by side and are paired here --
  # see ShiftCoveragePosition.entries_from_rows. Two flat lists rather than a
  # list of hashes: expect drops the rows of a [[...]] list given single
  # brackets.
  def post_params
    permitted = params.expect(shift_coverage_position: [:title, :count_only,
                                                        { row_position_ids: [], row_labels: [] }])
    ids = permitted.delete(:row_position_ids)
    labels = permitted.delete(:row_labels)
    permitted.merge(position_ids: ShiftCoveragePosition.entries_from_rows(ids, labels))
  end
end
