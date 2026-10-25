# frozen_string_literal: true

module DashboardTasks
  class VehicleRequests < DashboardTask
    def self.title
      "Personal Vehicle Request Eligible"
    end

    def self.skip_period
      [POST_EVENT, AFTER_EVENT]
    end

    def self.check(facts)
      if !facts.motorpool_agreement_available || (!facts.pvr_eligible && !facts.pvr_potential)
        return skip_task
      end

      vr = facts.vehicle_requests
      if vr.present?
        if vr.any? { |r| r.status == Vehicle::APPROVED }
          return completed(partial: "vehicle_requests_approved")
        elsif vr.any? { |r| r.status == Vehicle::PENDING }
          return waiting(partial: "vehicle_requests_pending")
        elsif vr.any? { |r| r.status == Vehicle::REJECTED }
          return urgent(partial: "vehicle_requests_denied")
        end
      end

      if facts.ignore_pvr
        return completed(title: "Personal Vehicle Request Eligible (Muted)", partial: "vehicle_requests_muted")
      end

      action_needed(partial: "vehicle_requests_eligible")
    end
  end
end
