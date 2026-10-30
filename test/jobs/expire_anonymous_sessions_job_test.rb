# frozen_string_literal: true

require "test_helper"

class ExpireAnonymousSessionsJobTest < ActiveSupport::TestCase
  test "perform removes idle anonymous rows and keeps fresh ones and every sign-in" do
    idle = anonymous_row((Session::ANONYMOUS_IDLE_DAYS + 1).days.ago)
    fresh = anonymous_row(1.day.ago)
    old_sign_in = person(:active_ranger).sessions.create!(session_id: SecureRandom.hex(32))
    old_sign_in.update_columns(created_at: 2.years.ago, updated_at: 2.years.ago)

    ExpireAnonymousSessionsJob.perform_now

    assert_not Session.exists?(idle.id)
    assert Session.exists?(fresh.id)
    assert Session.exists?(old_sign_in.id), "a sign-in is never swept, however old"
  end

  test "expire_anonymous reports how many rows went" do
    anonymous_row(40.days.ago)
    anonymous_row(50.days.ago)

    assert_equal 2, Session.expire_anonymous
  end

  private

  # A row as the Rack session store writes one: no person, data, touched at +at+.
  def anonymous_row(at)
    Session.insert({ session_id: SecureRandom.hex(16), data: "", created_at: at, updated_at: at }, record_timestamps: false)
    Session.where(person_id: nil).order(:id).last
  end
end
