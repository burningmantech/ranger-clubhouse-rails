# frozen_string_literal: true

# Marks off site everyone the event no longer holds, on the Saturday, Sunday
# and Monday after Labor Day. config/recurring.yml wakes this each morning of
# September 6-14, the only dates those three days can fall on; which of them
# they are moves with the year, so the job checks the day itself.
class OnSiteCleanupJob < ApplicationJob
  DAYS_AFTER_LABOR_DAY = (5..7)

  def perform
    labor_day = EventDate.first_monday_of_september(Current.year).to_date
    return unless DAYS_AFTER_LABOR_DAY.cover?((Current.today - labor_day).to_i)

    OnSiteCleanup.new.run!
  end
end
