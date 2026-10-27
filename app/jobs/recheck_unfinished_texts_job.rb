# frozen_string_literal: true

# Asks Twilio about each text still waiting for a receipt half a day after it
# went (SmsService.recheck_unfinished_texts). Daily, in production only and
# never on the training server: config/recurring.yml.
class RecheckUnfinishedTextsJob < ApplicationJob
  def perform = SmsService.recheck_unfinished_texts
end
