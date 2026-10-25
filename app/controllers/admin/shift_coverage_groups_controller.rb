# frozen_string_literal: true

# The shift types the Shift Coverage report can be run for: the menu it offers,
# the slug each one answers to, and the positions whose shifts set its rows.
# Each shift type's page lists the posts (the report's columns) it shows.
class Admin::ShiftCoverageGroupsController < Admin::ShiftCoverageBaseController
  before_action :set_group, only: [:show, :edit, :update, :destroy, :move]

  def index
    @groups = ShiftCoverageGroup.ordered.to_a
    @post_counts = ShiftCoveragePosition.group(:shift_coverage_group_id).count
    @positions_by_id = positions_by_id(@groups.flat_map(&:base_position_ids))
  end

  def show
    @posts = @group.shift_coverage_positions.to_a
    @positions_by_id = positions_by_id(@group.base_position_ids + @posts.flat_map(&:position_id_list))
  end

  def new
    @group = ShiftCoverageGroup.new
  end

  def create
    @group = ShiftCoverageGroup.new(group_params)
    # A new shift type joins the end of the menu; moving it is a separate step.
    @group.sort_index = @group.next_sort_index

    return render(:new, status: :unprocessable_entity) unless @group.save

    redirect_to admin_shift_coverage_group_path(@group), success: "Shift type created."
  end

  def edit
  end

  def update
    return render(:edit, status: :unprocessable_entity) unless @group.update(group_params)

    redirect_to admin_shift_coverage_group_path(@group), success: "Shift type updated."
  end

  # Its posts go with it, each one logged.
  def destroy
    @group.destroy!

    redirect_to admin_shift_coverage_groups_path,
                success: "\"#{@group.title}\" and its posts deleted."
  end

  # One step up or down the menu. The whole line is renumbered, so an order that
  # skipped or repeated numbers comes back in step.
  def move
    move_in_line(@group, admin_shift_coverage_groups_path, "The shift type order has been updated.",
                 "\"#{@group.title}\" is already at that end.")
  end

  private

  def set_group
    @group = ShiftCoverageGroup.find(params.expect!(:id))
  end

  def positions_by_id(ids)
    Position.where(id: ids.uniq).select(:id, :title, :active).index_by(&:id)
  end

  # Never scoped_params: a list that arrives empty has to clear the stored one
  # and be refused, not be read as nothing sent.
  def group_params
    params.expect(shift_coverage_group: [:slug, :title, base_position_ids: []])
  end
end
