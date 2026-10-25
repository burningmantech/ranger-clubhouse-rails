# frozen_string_literal: true

# Tells the vehicle request reviewers that requests are waiting on them.
class VehiclePendingJob < ApplicationJob
  def perform
    return if Setting.get_value(Setting::VEHICLE_PENDING_EMAIL).blank?

    pending = Vehicle.find_all_pending
    return if pending.empty?

    VehiclePendingMailer.notify(pending:).deliver_now
  end
end
