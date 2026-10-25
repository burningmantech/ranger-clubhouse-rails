# frozen_string_literal: true

require "test_helper"

class VehiclePendingJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    Setting.find_or_initialize_by(name: Setting::VEHICLE_PENDING_EMAIL).update!(value: "fleet@example.com")
  end

  test "perform mails the reviewers about requests waiting for them" do
    pending = vehicle(:pending_vehicle)

    assert_emails 1 do
      VehiclePendingJob.perform_now
    end

    mail = ActionMailer::Base.deliveries.last

    assert_equal ["fleet@example.com"], mail.to
    assert_includes mail.body.to_s, pending.person.callsign
    assert_includes mail.body.to_s, pending.vehicle_model
    assert_includes mail.body.to_s, %(href="http://example.com/vehicles/registry?status=pending&amp;type=personal")
  end

  test "perform sends nothing when nothing is waiting" do
    Vehicle.pending.update_all(status: Vehicle::APPROVED)

    assert_emails 0 do
      VehiclePendingJob.perform_now
    end
  end

  test "perform sends nothing when no address is set" do
    Setting.find_or_initialize_by(name: Setting::VEHICLE_PENDING_EMAIL).update!(value: "")

    assert_emails 0 do
      VehiclePendingJob.perform_now
    end
  end
end
