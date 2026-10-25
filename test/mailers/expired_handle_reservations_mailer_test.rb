# frozen_string_literal: true

require "test_helper"

class ExpiredHandleReservationsMailerTest < ActionMailer::TestCase
  test "notify renders expired handle details" do
    mail = ExpiredHandleReservationsMailer.notify(
      handles: [
        {
          "handle" => "Old News",
          "type" => "Ranger term",
          "reason" => "expired reason",
          "expires_on" => "2026-04-07"
        }
      ]
    )

    assert_equal [EmailAddresses::VOLUNTEER_COORDINATORS_TEAM], mail.to
    assert_equal "Expired Handle Reservations", mail.subject

    body = mail.body.to_s
    assert_includes body, "Old News"
    assert_includes body, "Ranger term"
    assert_includes body, "expired reason"
    assert_includes body, "2026-04-07"
  end
end
