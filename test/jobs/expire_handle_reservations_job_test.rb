# frozen_string_literal: true

require "test_helper"

class ExpireHandleReservationsJobTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include ActionMailer::TestHelper

  setup do
    travel_to Time.zone.local(2026, 4, 8, 9, 0, 0)
    ActionMailer::Base.deliveries.clear
    HandleReservation.delete_all
  end

  teardown do
    travel_back
    ActionMailer::Base.deliveries.clear
  end

  test "perform deletes expired reservations and sends email" do
    expired = HandleReservation.create!(
      handle: "Old News",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM,
      expires_on: Current.today - 1.day,
      reason: "expired reason"
    )
    active = HandleReservation.create!(
      handle: "Still Good",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM,
      expires_on: Current.today + 1.day
    )

    assert_emails 1 do
      ExpireHandleReservationsJob.perform_now
    end

    assert_not HandleReservation.exists?(expired.id)
    assert HandleReservation.exists?(active.id)

    body = ActionMailer::Base.deliveries.last.body.to_s
    assert_includes body, "Old News"
    assert_includes body, "Ranger term"
    assert_includes body, "expired reason"
  end

  test "perform does not send email when nothing expires" do
    HandleReservation.create!(
      handle: "No Expiry",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM,
      expires_on: Current.today + 3.days
    )

    assert_emails 0 do
      ExpireHandleReservationsJob.perform_now
    end
  end
end
