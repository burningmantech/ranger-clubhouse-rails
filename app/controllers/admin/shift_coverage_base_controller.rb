# frozen_string_literal: true

# What the two Shift Coverage Management controllers share: the layout, who may
# reach them, the positions their forms offer, and the move that puts a shift
# type or a post one place up or down its line.
class Admin::ShiftCoverageBaseController < ApplicationController
  include LineMoveConcern

  layout "admin"

  # Admin passes no gate implicitly through authorize_role, so both roles are
  # named. AdminMenuTest compares the menu item with this list.
  authorize_role [Role::ADMIN, Role::TECH_NINJA],
                 message: "Admin or Tech Ninja role required to manage shift coverage."

  before_action :load_positions, only: [:new, :create, :edit, :update]

  private

  # Every position, inactive ones included: several shift types and posts are
  # seeded with one, and a form that hid it would drop it on the next save.
  # team_id is for the team groups the post form's select draws.
  def load_positions
    @positions = Position.ordered_by_title.select(:id, :title, :active, :team_id)
  end
end
