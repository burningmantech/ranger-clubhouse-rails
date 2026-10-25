# frozen_string_literal: true

require "test_helper"

class ExpireAnnouncementsJobTest < ActiveSupport::TestCase
  test "perform deletes expired announcements and leaves active ones" do
    expired = motd(:expired_ranger_announcement)
    active = motd(:ranger_announcement)
    PersonMotd.create!(person_id: person(:active_ranger).id, motd_id: expired.id, read_at: Current.time)

    ExpireAnnouncementsJob.perform_now

    assert_not Motd.exists?(expired.id)
    assert Motd.exists?(active.id)
    assert_empty PersonMotd.where(motd_id: expired.id)
  end
end
