# frozen_string_literal: true

module RolesHelper
  def has_role?(role)
    user = current_user
    return false if user.nil?

    roles = Array.wrap(role)
  end
end
