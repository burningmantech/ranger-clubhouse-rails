# frozen_string_literal: true

class Admin::PermissionsController < ApplicationController
  layout "admin"

  authorize_role [Role::ADMIN, Role::TECH_NINJA]

  # admin: false -- reading the catalog is open to both roles, but only the Tech
  # Team may change it. The same gate answers the buttons in the view, so the
  # affordance and the guard cannot disagree.
  authorize_ability :manage_permissions,
                    only: [:edit, :update, :destroy, :new_art, :create_art],
                    roles: [Role::TECH_NINJA],
                    admin: false,
                    deny_to: :admin_permissions_path,
                    message: "You are not authorized to change permissions."

  before_action :set_permission, only: [:edit, :update, :destroy]
  before_action :count_holders, only: [:edit, :update]

  def index
    @named_permissions, @composed_groups = Role.catalog
  end

  def edit
  end

  def update
    if @permission.update(permission_params)
      purge_role_cache
      redirect_to admin_permissions_path, success: "Permission updated."
      return
    end

    render :edit, status: :unprocessable_entity
  end

  def destroy
    if @permission.protected_role?
      redirect_to admin_permissions_path,
                  error: "#{@permission.title} cannot be deleted. Everyone who holds it would " \
                         "lose it, and no page would be left that could grant it back."
      return
    end

    title = @permission.title
    @permission.destroy
    purge_role_cache
    redirect_to admin_permissions_path, success: "#{title} deleted."
  end

  def new_art
    @art_form = ArtPermissionForm.new
    @art_positions = art_positions
  end

  def create_art
    @art_form = ArtPermissionForm.new(art_params)

    return render_art_form unless @art_form.valid?

    created, existing = Role.create_art_roles(@art_form.position_id)
    purge_role_cache
    redirect_to admin_permissions_path, success: art_result_message(created, existing)
  rescue ArgumentError, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique => e
    # Unreachable from the picker, which only offers positions that pass every
    # check. A hand-built request lands here.
    @art_form.errors.add(:position_id, e.message)
    render_art_form
  end

  private

  def set_permission
    @permission = Role.with_associations.find(params.expect!(:id))
  end

  # Counted before a rejected form re-renders, so the delete confirmation names
  # what the record actually holds.
  def count_holders
    @held_by_people = PersonRole.where(role_id: @permission.id).count
  end

  def permission_params
    params.expect(role: [:title, :new_user_eligible])
  end

  def art_params
    params.expect(art_permission_form: [:position_id])
  end

  # Only positions that would pass every check inside create_art_roles, so the
  # picker cannot offer a choice the save refuses.
  def art_positions
    Position.find_for_query({ art_training: true, active: true })
  end

  def render_art_form
    @art_positions = art_positions
    render :new_art, status: :unprocessable_entity
  end

  def art_result_message(created, existing)
    parts = []
    parts << "Created #{helpers.pluralize(created.size, "permission")}." if created.any?
    parts << "#{helpers.pluralize(existing.size, "permission")} already existed." if existing.any?
    parts.join(" ")
  end

  # Every change here alters what roles a person resolves to, and those are
  # cached per person. Clearing the whole cache rather than matching a prefix
  # follows the position and team role writers: solid_cache has no
  # delete_matched.
  def purge_role_cache
    RoleManager.purge_all
  end
end
