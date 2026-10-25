# frozen_string_literal: true

# A dashboard task is a pure rule: facts -> Verdict.
#
# Each task is a subclass that implements +self.check(facts)+ returning a
# DashboardTaskResult (the verdict). Filtering/placement metadata (+period+,
# +skip_period+, +immediate+) and +title+ are class methods with defaults here.
# There is no instance state — the orchestrator calls +TaskClass.check(facts)+.
class DashboardTask
  STATUS_ACTION_NEEDED = :action_needed
  STATUS_BLOCKED = :blocked
  STATUS_COMPLETED = :completed
  STATUS_NOTE = :note
  STATUS_NOT_AVAILABLE = :not_available
  STATUS_OPTIONAL = :optional
  STATUS_SKIP = :skip
  STATUS_URGENT = :urgent
  STATUS_WAITING = :waiting

  BEFORE_EVENT = "before-event"
  # Event week is happening
  DURING_EVENT = "event"
  # Event is over with, timesheet corrections still may be happening, surveys still open
  POST_EVENT = "post-event"
  # The off-season, nothing really happening.
  AFTER_EVENT = "after-event"

  # --- placement / filtering metadata (override per task) ---
  def self.title = nil
  def self.period = []
  def self.skip_period = []
  def self.immediate = false

  # --- the one lifecycle method (override per task) ---
  def self.check(_facts)
    raise NotImplementedError, "#{name} must implement self.check(facts)"
  end

  # --- verdict factory methods ---
  #
  # Each names the outcome and stamps the matching STATUS_* on the verdict, so a
  # call site reads +urgent(partial: "missing_bpguid")+ instead of hand-rolling
  # +DashboardTaskResult.new(result: STATUS_URGENT, partial: ...)+. The status and
  # the field-set stop being a guessing game.
  def self.skip_task
    DashboardTaskResult.new(result: STATUS_SKIP)
  end

  def self.completed_task
    DashboardTaskResult.new(result: STATUS_COMPLETED)
  end

  def self.urgent(partial:, immediate: false, payload: nil)
    DashboardTaskResult.new(result: STATUS_URGENT, partial:, immediate:, payload:)
  end

  def self.action_needed(partial:, immediate: false, payload: nil)
    DashboardTaskResult.new(result: STATUS_ACTION_NEEDED, partial:, immediate:, payload:)
  end

  def self.waiting(partial:)
    DashboardTaskResult.new(result: STATUS_WAITING, partial:)
  end

  def self.not_available(partial:)
    DashboardTaskResult.new(result: STATUS_NOT_AVAILABLE, partial:)
  end

  def self.optional(partial:)
    DashboardTaskResult.new(result: STATUS_OPTIONAL, partial:)
  end

  def self.blocked(partial:)
    DashboardTaskResult.new(result: STATUS_BLOCKED, partial:)
  end

  def self.note(partial:, title: nil)
    DashboardTaskResult.new(result: STATUS_NOTE, partial:, title:)
  end

  def self.completed(partial: nil, sticky: false, title: nil, payload: nil)
    DashboardTaskResult.new(result: STATUS_COMPLETED, partial:, sticky:, title:, payload:)
  end
end
