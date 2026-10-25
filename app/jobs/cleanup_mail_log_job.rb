# frozen_string_literal: true

# Throws away sent messages once they are old enough that no one looks them up
# any more. The log is one of the largest tables in the Clubhouse.
class CleanupMailLogJob < ApplicationJob
  def perform
    count = MailLog.purge_old
    Rails.logger.info("Mail log cleanup removed #{count} #{'message'.pluralize(count)}")
  end
end
