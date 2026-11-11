# frozen_string_literal: true

# Words for the Person › Schedule Audit Log, the page that shows what
# ScheduleLog returns.
module Person::SchedulingHelper
  # What a change the person made themselves reads as "by"; the card's question
  # about it quotes it from here.
  SCHEDULE_LOG_SELF = "self"

  # Each override ScheduleLog reports: its badge, and what the page's card says
  # it means. The badges and the card's legend both read this.
  SCHEDULE_LOG_OVERRIDES = {
    overcapacity: ["Over Capacity", "The shift was already full."],
    after_start: ["After Shift Start", "The shift had already begun."],
    multiple_enrollment: ["Multiple Enrollment",
                          "They were already signed up for another session of the same training, or another Alpha shift."],
    trainer_forced: ["Trainer Forced", "A trainer signed them up for a second session of the same training."],
    unsigned_sandman_affidavit: ["Unsigned Sandman Affidavit", "The Sandman affidavit was not yet signed."]
  }.freeze

  def schedule_log_override_badge(override)
    ui_badge SCHEDULE_LOG_OVERRIDES.fetch(override).first, :warning
  end

  # A removal's stored reason, in the page's words.
  def schedule_log_reason(reason)
    reason == "slot deletion" ? "Shift deleted" : reason.upcase_first
  end
end
