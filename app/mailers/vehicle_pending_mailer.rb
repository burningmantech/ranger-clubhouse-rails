# frozen_string_literal: true

class VehiclePendingMailer < ApplicationMailer
  def notify(pending:)
    liquid_assigns.merge!(
      count: pending.count,
      registry_url: vehicles_registry_index_url(status: Vehicle::PENDING, type: Vehicle::PERSONAL),
      vehicles: pending.map do |vehicle|
        {
          callsign: vehicle.person.callsign,
          description: [vehicle.vehicle_year, vehicle.vehicle_make,
                        vehicle.vehicle_model, vehicle.vehicle_color].join(" "),
          submitted_at: vehicle.created_at.to_s
        }
      end
    )

    mail(
      from: do_not_reply_from,
      to: build_addresses(Setting.get_value(Setting::VEHICLE_PENDING_EMAIL)),
      subject: liquid_subject
    )
  end
end
