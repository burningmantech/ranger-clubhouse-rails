# frozen_string_literal: true

module Scheduling::Management
  # Thin delegating shim kept ONLY for safety during the migration to the deep
  # Scheduling::Signup module. All scheduling-write behaviour now lives in
  # Scheduling::Signup / Scheduling::Signup::Bulk; this forwards verbatim so any caller or
  # test still naming Scheduling::Management resolves identically.
  #
  # CONTEXT.md lists Management under "Avoid" -- once every caller and test is migrated to
  # Scheduling::Signup this file is deleted.

  # Keep Scheduling::Management::SignupResult resolving (verdict_test, controller test).
  SignupResult = Scheduling::Signup::SignupResult

  module_function

  def add_to_schedule(person, slot, want_to_force = false)
    Scheduling::Signup.add(person, slot, want_to_force)
  end

  def remove_from_schedule(person, slot, want_to_force = false)
    Scheduling::Signup.remove(person, slot, want_to_force)
  end

  def remove_future_sign_ups(person_id, reason)
    Scheduling::Signup::Bulk.remove_future_sign_ups(person_id, reason)
  end

  def remove_future_sign_ups_for_position(person_id, position_id, reason)
    Scheduling::Signup::Bulk.remove_future_sign_ups_for_position(person_id, position_id, reason)
  end

  # Internal write-path methods retained as thin forwarders so the existing
  # signup-store / capacity characterization tests (which reach in via +send+) keep
  # exercising the same code through Scheduling::Signup.
  def create_signup(person_id, slot, force: false)
    Scheduling::Signup.send(:create_signup, person_id, slot, force: force)
  end

  def delete_signup(person_id, slot, reason: nil, forced: false)
    Scheduling::Signup.send(:delete_signup, person_id, slot, reason: reason, forced: forced)
  end

  def compute_signups(slot, result, force)
    Scheduling::Signup.send(:compute_signups, slot, result, force)
  end
end
