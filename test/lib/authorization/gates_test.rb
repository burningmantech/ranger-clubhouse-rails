# frozen_string_literal: true

require "test_helper"

# The gates are pure predicates over a Context, so they unit-test with a plain stub — no
# HTTP, no Current, no fixtures. This is the testability the hand-rolled require_*! predicates
# never had.
class Authorization::GatesTest < ActiveSupport::TestCase
  Ctx = Struct.new(:admin, :roles, :event_mgmt, :current_year, keyword_init: true) do
    def admin? = admin
    def has_role?(wanted) = (Array(roles) & Array(wanted)).any?
    def has_event_management? = event_mgmt
    def current_year? = current_year
  end

  def ctx(admin: false, roles: [], event_mgmt: false, current_year: true)
    Ctx.new(admin:, roles:, event_mgmt:, current_year:)
  end

  test "RoleGate: admin passes implicitly" do
    gate = Authorization::RoleGate.new(roles: [99], deny_to: :x, message: "m")
    assert gate.permits?(ctx(admin: true))
  end

  test "RoleGate: admin:false excludes admin, still honours the role list" do
    gate = Authorization::RoleGate.new(roles: [99], admin: false, deny_to: :x, message: "m")
    assert_not gate.permits?(ctx(admin: true))
    assert gate.permits?(ctx(roles: [99]))
  end

  test "RoleGate: matches any listed role" do
    gate = Authorization::RoleGate.new(roles: [1, 2], deny_to: :x, message: "m")
    assert gate.permits?(ctx(roles: [2]))
    assert_not gate.permits?(ctx(roles: [3]))
  end

  test "RoleGate: extra predicate is OR'd in" do
    gate = Authorization::RoleGate.new(roles: [], admin: false, extra: :has_event_management?, deny_to: :x, message: "m")
    assert gate.permits?(ctx(event_mgmt: true))
    assert_not gate.permits?(ctx(event_mgmt: false))
  end

  test "YearGate: satisfied only on the current year — denies admins on past years" do
    gate = Authorization::YearGate.new(deny_to: :x, message: "m")
    assert gate.satisfied?(ctx(current_year: true, admin: true))
    assert_not gate.satisfied?(ctx(current_year: false, admin: true))
  end
end
