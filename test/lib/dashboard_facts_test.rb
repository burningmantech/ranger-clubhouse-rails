# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardFactsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "literal construction exposes given attrs, leaves the rest nil, and freezes" do
    facts = DashboardFacts.new(period: "event", did_work: true, is_applicant: false)

    assert_equal "event", facts.period
    assert facts.did_work
    assert_nil facts.training
    assert facts.frozen?
  end

  test "rejects unknown attributes" do
    error = assert_raises(ArgumentError) { DashboardFacts.new(bogus_attr: 1) }
    assert_match "bogus_attr", error.message
  end

  test "the partial-reached readers are first-class facts that default to nil" do
    # These five were previously smuggled into partials via the raw Milestones object;
    # they are now part of the seam surface (MILESTONE_ATTRS).
    new_readers = %i[
      alpha_shift_prep_link alpha_shift_publish_date
      needs_full_training is_binary ts_mentor_survey_url
    ]

    new_readers.each do |reader|
      assert_includes DashboardFacts::MILESTONE_ATTRS, reader, "#{reader} should be a milestone fact"
    end

    facts = DashboardFacts.new(period: "event")
    new_readers.each do |reader|
      assert_nil facts.public_send(reader), "#{reader} should default to nil under literal construction"
    end
  end

  test "with_prev_completed derives a new frozen sibling and leaves the original untouched" do
    facts = DashboardFacts.new(period: "event", prev_completed: false)

    derived = facts.with_prev_completed(true)

    assert derived.prev_completed
    assert_equal "event", derived.period
    assert derived.frozen?
    refute facts.prev_completed
  end

  test "from_milestones copies every milestone attr, the person predicates, status and now" do
    milestone_values = DashboardFacts::MILESTONE_ATTRS.index_with { |attr| "value_#{attr}" }
    milestones = OpenStruct.new(milestone_values)
    person = Class.new do
      def status = "active"
      def is_applicant? = true
      def is_echelon? = false
      def is_auditor? = false
      def is_any_bonked? = false
    end.new
    travel_to Time.zone.local(2026, 8, 25, 12, 0, 0) do
      facts = DashboardFacts.from_milestones(milestones, person)

      DashboardFacts::MILESTONE_ATTRS.each do |attr|
        assert_equal "value_#{attr}", facts.public_send(attr), "#{attr} was not copied from milestones"
      end
      assert_equal "active", facts.status
      assert facts.is_applicant
      refute facts.is_echelon
      # travel_to freezes the clock, so the instant read inside from_milestones is still the current one.
      assert_equal Time.current, facts.now
      refute facts.prev_completed
    end
  end
end
