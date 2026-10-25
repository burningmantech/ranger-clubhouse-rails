# frozen_string_literal: true

# Self-serve shift check in/out — the person starts and ends their own
# shifts. Ported from the Ember Me > Timesheet "Shift Check In/Out" tab;
# the actions and shared views come from ShiftManageConcern.
class Me::ShiftManageController < ApplicationController
  include ShiftManageConcern

  layout "me"

  authorize_role [Role::ADMIN, Role::SHIFT_MANAGEMENT_SELF],
                 message: "The Shift Management Self permission is required to check in and out of shifts."

  def index
    load_shift_manage_state
  end

  private

  def shift_person = current_user

  def shift_self_serve? = true

  def shift_return_path = me_shift_manage_path

  def shift_start_path(**params) = me_shift_manage_start_path(**params)

  def shift_end_path(**params) = me_shift_manage_end_path(**params)

  def shift_resignin_path(**params) = me_shift_manage_resignin_path(**params)

  def shift_correct_position_path(**params) = me_shift_manage_position_path(**params)

  def shift_delete_mistake_path(**params) = me_shift_manage_entry_path(**params)
end
