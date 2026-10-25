# frozen_string_literal: true

module AuthorizeHelper
  extend ActiveSupport::Concern

  included do
    if respond_to?(:class_attribute)
      class_attribute :authorized_roles, instance_accessor: false, default: nil
      class_attribute :authorized_roles_message, instance_accessor: false, default: nil
      class_attribute :authorized_statuses, instance_accessor: false, default: nil
      class_attribute :authorized_statuses_except, instance_accessor: false, default: nil
      class_attribute :authorized_statuses_message, instance_accessor: false, default: nil

      # Per-action ability gates (see authorize_ability / require_current_year_for).
      class_attribute :role_gates, instance_accessor: false, default: {}
      class_attribute :year_gate, instance_accessor: false, default: nil
    end

    helper_method :can? if respond_to?(:helper_method)
  end

  class_methods do
    def authorize_role(roles, message: nil)
      self.authorized_roles = Array.wrap(roles).freeze
      self.authorized_roles_message = message
    end

    def authorize_status(statuses = nil, except: nil, message: nil)
      if !statuses.nil? && !except.nil?
        raise ArgumentError, "authorize_status accepts statuses or except:, not both"
      end

      if statuses.nil? && except.nil?
        raise ArgumentError, "authorize_status requires statuses or except:"
      end

      self.authorized_statuses = statuses.nil? ? nil : Array.wrap(statuses).freeze
      self.authorized_statuses_except = except.nil? ? nil : Array.wrap(except).freeze
      self.authorized_statuses_message = message
    end

    def deny_status(statuses, message: nil)
      authorize_status(except: statuses, message:)
    end

    # Declare a per-action role ability. The SAME gate backs both the before_action guard
    # and the can?(name) view affordance, so they cannot drift.
    def authorize_ability(name, only: nil, except: nil, **opts)
      self.role_gates = role_gates.merge(name => Authorization::RoleGate.new(**opts))
      before_action(only:, except:) { enforce_ability!(name) }
    end

    # Declare a role-free current-year write gate as its own before_action.
    def require_current_year_for(only: nil, except: nil, **opts)
      self.year_gate = Authorization::YearGate.new(**opts)
      before_action(only:, except:) { enforce_current_year! }
    end
  end

  def enforce_ability!(name)
    gate = self.class.role_gates.fetch(name)
    return true if gate.permits?(authorization_context)

    redirect_to send(gate.deny_to), error: deny_message_for(gate)
    false
  end

  def enforce_current_year!
    gate = self.class.year_gate
    return true if gate.satisfied?(authorization_context)

    redirect_to send(gate.deny_to), error: deny_message_for(gate)
    false
  end

  # View affordance — same predicate the server guard uses.
  def can?(name)
    self.class.role_gates.fetch(name).permits?(authorization_context)
  end

  private

  def authorization_context
    Authorization::Context.new(self)
  end

  def deny_message_for(gate)
    gate.message.is_a?(Symbol) ? send(gate.message) : gate.message
  end
end
