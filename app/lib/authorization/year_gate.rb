# frozen_string_literal: true

module Authorization
  # "Is this the writable year?" — a ROLE-FREE gate that denies everyone, admins included,
  # on a past year. Modeled separately from RoleGate precisely so the implicit-admin pass
  # cannot wrongly grant past-year writes.
  class YearGate
    attr_reader :deny_to, :message

    def initialize(deny_to:, message:)
      @deny_to = deny_to
      @message = message
    end

    def satisfied?(context)
      context.current_year?
    end
  end
end
