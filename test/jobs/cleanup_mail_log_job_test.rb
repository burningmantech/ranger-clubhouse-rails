# frozen_string_literal: true

require "test_helper"

class CleanupMailLogJobTest < ActiveSupport::TestCase
  test "perform removes messages past the retention window and keeps the rest" do
    MailLog.delete_all
    old = create_log(created_at: (MailLog::RETENTION + 1.day).ago)
    recent = create_log(created_at: 1.day.ago)

    CleanupMailLogJob.perform_now

    assert_not MailLog.exists?(old.id)
    assert MailLog.exists?(recent.id)
  end

  private

  def create_log(created_at:)
    log = MailLog.create!(person_id: person(:active_ranger).id, from_email: "do-not-reply@burningman.org",
                          to_email: "volunteer@example.com", message_id: "msg-#{SecureRandom.hex(8)}",
                          subject: "Anything")
    log.update_column(:created_at, created_at)
    log
  end
end
