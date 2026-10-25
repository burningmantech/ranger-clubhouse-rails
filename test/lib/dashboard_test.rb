# frozen_string_literal: true

require "test_helper"

# Exercises the deepened orchestrator with FAKE tasks + literal facts — no DB, no fixtures.
# This is the coverage the old shape could not have: the gating, sorting, binning, skip-drop
# and prev_completed threading are now testable through one seam.
class DashboardTest < ActiveSupport::TestCase
  ST = DashboardTask

  # Build a one-off task class implementing the new contract.
  def fake_task(result:, partial:, immediate: false, period: [], skip_period: [], title: "Title", echo_prev: false)
    Class.new(DashboardTask) do
      define_singleton_method(:title) { title }
      define_singleton_method(:period) { period }
      define_singleton_method(:skip_period) { skip_period }
      define_singleton_method(:immediate) { immediate }
      define_singleton_method(:check) do |facts|
        DashboardTaskResult.new(
          result:,
          partial: echo_prev ? facts.prev_completed.to_s : partial
        )
      end
    end
  end

  def facts(period: "event", **overrides)
    DashboardFacts.new(period:, **overrides)
  end

  def process(step_classes, facts_obj = facts)
    Dashboard.new(facts_obj).send(:process_step_group, step_classes)
  end

  # --- gating -------------------------------------------------------------

  test "skip_period blacklists the current period" do
    task = fake_task(result: ST::STATUS_URGENT, partial: "u", skip_period: ["event"])
    out = process([task], facts(period: "event"))
    assert_empty out.values.flatten, "task in a blacklisted period should be filtered out entirely"
  end

  test "period whitelists: filtered when current period is not in the list" do
    task = fake_task(result: ST::STATUS_URGENT, partial: "u", period: ["before-event"])
    assert_empty process([task], facts(period: "event")).values.flatten
    refute_empty process([task], facts(period: "before-event")).values.flatten
  end

  # --- skip-drop ----------------------------------------------------------

  test "a STATUS_SKIP verdict is dropped from every bin" do
    task = fake_task(result: ST::STATUS_SKIP, partial: "s")
    assert_empty process([task]).values.flatten
  end

  # --- binning ------------------------------------------------------------

  test "verdicts route to immediate / note / completed / steps bins" do
    immediate = fake_task(result: ST::STATUS_URGENT, partial: "imm", immediate: true)
    note = fake_task(result: ST::STATUS_NOTE, partial: "note")
    completed = fake_task(result: ST::STATUS_COMPLETED, partial: "done")
    action = fake_task(result: ST::STATUS_ACTION_NEEDED, partial: "act")

    out = process([immediate, note, completed, action])

    assert_equal ["imm"], out[:immediate_steps].map(&:partial)
    assert_equal ["note"], out[:note].map(&:partial)
    assert_equal ["done"], out[:completed].map(&:partial)
    assert_equal ["act"], out[:steps].map(&:partial)
  end

  # --- sorting ------------------------------------------------------------

  test "steps are sorted by result priority, stable within a tie" do
    optional = fake_task(result: ST::STATUS_OPTIONAL, partial: "opt")
    urgent = fake_task(result: ST::STATUS_URGENT, partial: "urg")
    action_a = fake_task(result: ST::STATUS_ACTION_NEEDED, partial: "act_a")
    action_b = fake_task(result: ST::STATUS_ACTION_NEEDED, partial: "act_b")

    out = process([optional, action_a, urgent, action_b])

    # urgent(1) < action_needed(2, insertion-stable) < optional(6)
    assert_equal %w[urg act_a act_b opt], out[:steps].map(&:partial)
  end

  # --- is_active ----------------------------------------------------------

  test "first actionable step is marked active" do
    urgent = fake_task(result: ST::STATUS_URGENT, partial: "urg")
    waiting = fake_task(result: ST::STATUS_WAITING, partial: "wait")

    out = process([waiting, urgent])
    active = out[:steps].select(&:is_active).map(&:partial)

    assert_includes active, "urg"
  end

  # --- title backfill -----------------------------------------------------

  test "a verdict without a title inherits the task's class title" do
    task = fake_task(result: ST::STATUS_ACTION_NEEDED, partial: "act", title: "Do The Thing")
    out = process([task])
    assert_equal "Do The Thing", out[:steps].first.title
  end

  # --- view contract: every branch returns StepGroups -----------------------

  test "auditor groups satisfy the StepGroup view contract" do
    [DashboardFactsFactory.for(:auditor), DashboardFactsFactory.for(:auditor_offseason)].each do |auditor_facts|
      groups = Dashboard.new(auditor_facts).groups
      refute_empty groups
      groups.each do |group|
        assert_respond_to group, :steps, "the dashboard views call group.steps on every entry"
        assert_respond_to group, :title
        group.steps.each { |step| assert step.title.present?, "every step needs a title for its accent card heading" }
      end
    end
  end

  # --- prev_completed threading (applicant/auditor cascade) ----------------

  test "evaluate_step threads prev_completed into the facts the task sees" do
    task = fake_task(result: ST::STATUS_ACTION_NEEDED, partial: "ignored", echo_prev: true)
    dashboard = Dashboard.new(facts)

    completed = dashboard.send(:evaluate_step, task, prev_completed: true)
    not_completed = dashboard.send(:evaluate_step, task, prev_completed: false)

    assert_equal "true", completed.partial
    assert_equal "false", not_completed.partial
  end
end
