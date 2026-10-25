# frozen_string_literal: true

module Authorization
  # "May this person do X here?" — a role/admin/extra predicate for one named ability.
  # ADMIN passes implicitly unless +admin: false+. The deny destination (+deny_to+, a
  # controller method name) and the deny message (a String, or a Symbol naming a controller
  # method for action-dependent text) travel with the gate.
  #
  # The SAME gate answers both the server guard and the view affordance (via #permits?), so
  # the two can never drift.
  class RoleGate
    attr_reader :deny_to, :message

    def initialize(deny_to:, message:, roles: [], admin: true, extra: nil)
      @roles = Array(roles)
      @admin = admin
      @extra = extra
      @deny_to = deny_to
      @message = message
    end

    def permits?(context)
      return true if @admin && context.admin?
      return true if @roles.any? && context.has_role?(@roles)
      return true if @extra && context.public_send(@extra)

      false
    end
  end
end
