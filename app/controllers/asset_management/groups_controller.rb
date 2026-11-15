# frozen_string_literal: true

# The asset groups the asset form offers, by asset type: add one, rename or
# retire it, and merge one into another. Groups span years, so nothing here is
# year-scoped.
class AssetManagement::GroupsController < ApplicationController
  layout "asset_management"

  authorize_ability :read_assets,
                    roles: [Role::EDIT_ASSETS, Role::EVENT_MANAGEMENT],
                    only: :index,
                    deny_to: :me_root_path,
                    message: "You are not authorized to view assets."

  authorize_ability :edit_assets,
                    roles: [Role::EDIT_ASSETS],
                    except: :index,
                    deny_to: :editor_denied_path,
                    message: "You are not authorized to manage assets."

  before_action :set_group, only: %i[edit update destroy merge merge_into]

  def index
    type_order = AssetManagement::RecordsHelper::ASSET_TYPE_SORT
    @groups_by_type = AssetGroup.by_title.group_by(&:type)
                                .sort_by { |type, _groups| [type_order.fetch(type, type_order.size), type] }
    @asset_counts = Asset.where.not(asset_group_id: nil).group(:asset_group_id).count
  end

  def new
    @group = AssetGroup.new(type: params[:type].presence || Asset::TYPE_RADIO)
  end

  def create
    @group = AssetGroup.new(group_params)

    if @group.save
      redirect_to asset_management_groups_path, success: "Asset group saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @group.update(group_params)
      redirect_to asset_management_groups_path, success: "Asset group saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @group.destroy
      redirect_to asset_management_groups_path, success: "Asset group deleted."
    else
      redirect_to edit_asset_management_group_path(@group), error: @group.errors.full_messages.join(" ")
    end
  end

  def merge
    @targets = merge_targets
  end

  # The target comes from this group's own type, whatever id was posted: a
  # group of another type, or this group itself, is not found.
  def merge_into
    target = merge_targets.find_by(id: params[:target_id].to_s)
    unless target
      return redirect_to merge_asset_management_group_path(@group),
                         error: "Pick the group to merge into. It must be another group of the same type."
    end

    moved = @group.merge_into!(target)
    redirect_to asset_management_groups_path,
                success: "#{@group.title} merged into #{target.title}. " \
                         "#{helpers.pluralize(moved, "asset")} moved."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    # The joined notes outgrew their column, or an asset joined the group mid-merge.
    redirect_to merge_asset_management_group_path(@group),
                error: "The merge could not finish and nothing was changed. #{e.record.errors.full_messages.join(" ")}"
  end

  private

  def set_group
    @group = AssetGroup.find(params[:id])
    @asset_count = @group.assets.count
  end

  def merge_targets
    AssetGroup.where(type: @group.type).where.not(id: @group.id).order(active: :desc, title: :asc)
  end

  def group_params
    params.expect(asset_group: %i[type title notes active])
  end

  def editor_denied_path
    can?(:read_assets) ? asset_management_groups_path : me_root_path
  end
end
