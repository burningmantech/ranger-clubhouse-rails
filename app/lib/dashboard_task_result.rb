# frozen_string_literal: true

# The verdict a dashboard task returns: a status symbol + a partial name + an
# optional per-task payload (CONTEXT.md's "nine statuses + a partial name +
# per-task payload").
#
# +result+ and +title+ are mutable because the orchestrator reassigns +result+
# (the applicant/auditor cascade demotes ACTION_NEEDED -> NOT_AVAILABLE) and
# backfills +title+ from the task's class title. +immediate+/+sticky+ steer
# placement; +is_active+/+sort_index+ are orchestrator scratch.
#
# Per-task payload (the only three values a partial actually reads off the
# verdict) rides in +payload+, a small carrier — see +Payload+.
class DashboardTaskResult
  # The per-task payload carrier. Only three values survive a full grep of the
  # task partials: +tickets+ + +ticketing_open+ (_dashboard_tickets) and +year+
  # (_ranger_interest_signup). Everything else a partial needs comes off +facts+.
  Payload = Data.define(:tickets, :ticketing_open, :year) do
    def initialize(tickets: nil, ticketing_open: nil, year: nil)
      super
    end
  end

  attr_accessor :title,
                :result,
                :partial,
                :immediate,
                :sticky,
                :sort_index,
                :is_active,
                :payload

  def initialize(attributes = {})
    attributes.each do |key, value|
      raise ArgumentError, "unknown DashboardTaskResult attribute: #{key}" unless respond_to?("#{key}=")
      send("#{key}=", value)
    end
  end
end
