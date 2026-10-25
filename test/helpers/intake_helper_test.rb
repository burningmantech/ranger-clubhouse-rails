# frozen_string_literal: true

require "test_helper"

# The pipeline row's grammar: one lead chip for the most serious mark, then
# everything else as text in team order.
class IntakeHelperTest < ActionView::TestCase
  include IntakeHelper
  include UiComponents::BadgeHelper
  include IconHelper
  include DateTimeHelper

  Subject = Struct.new(:status)

  # A summary the way Intake hands it over: the strip worst-first and
  # worst_rank already computed.
  def summary(personnel_issue: false, bonk: nil, ranks: [], status: Person::PROSPECTIVE)
    worst = ranks.map { |entry| entry[:rank] }.max_by { |rank| Intake::RANK_SEVERITY[rank] }
    { person: Subject.new(status), personnel_issue:, bonk:, ranks:, worst_rank: worst }
  end

  def rank(team, rank, year = 2026)
    { team:, rank:, year: }
  end

  test "the lead is the most serious mark: flag, uber-bonk, bonk, then rank" do
    bonk = { year: 2026, status: PersonMentor::STATUS_BONK }
    flag = rank("vc", Intake::FLAG)

    assert_match "Personnel flag", intake_lead_signal(summary(personnel_issue: true, bonk:, ranks: [flag]))
    assert_match "uber-bonked", intake_lead_signal(summary(status: Person::UBERBONKED, bonk:, ranks: [flag]))
    assert_match "2026 mentor bonked", intake_lead_signal(summary(bonk:, ranks: [flag]))
    assert_match "4/FLAG · VC 2026", intake_lead_signal(summary(ranks: [flag, rank("mentor", Intake::BELOW_AVERAGE)]))
  end

  test "calm ranks give no lead signal" do
    assert_nil intake_lead_signal(summary(ranks: [rank("training", Intake::ABOVE_AVERAGE), rank("vc", Intake::AVERAGE)]))
    assert_nil intake_lead_signal(summary)
  end

  test "the gray line lists ranks in team order, whatever order the strip has" do
    ranks = [rank("mentor", Intake::BELOW_AVERAGE, 2025), rank("training", Intake::ABOVE_AVERAGE, 2024),
             rank("rrn", Intake::FLAG, 2023)]

    assert_equal "RRN 4/FLAG (2023) · Training 1/Green (2024) · Mentor 3/Yellow (2025)", intake_ranks_text(ranks)

    notes = [{ team: "personnel", latest_at: Time.zone.local(2026, 6, 8) },
             { team: "vc", latest_at: Time.zone.local(2026, 3, 20) }]

    assert_equal "Personnel Jun 8, 2026 · VC Mar 20, 2026", intake_notes_text(notes)
  end

  # person_intake_note.created_at and trainee_note.created_at allow NULL. A
  # note without one still names its team, with no dangling date after it.
  test "a note with no timestamp is named by its team alone" do
    notes = [{ team: "personnel", latest_at: nil }, { team: "vc", latest_at: Time.zone.local(2026, 3, 20) }]

    assert_equal "Personnel · VC Mar 20, 2026", intake_notes_text(notes)
  end

  # "Trained" is the expected state and carries no colour; the exceptions keep
  # their icon and colour so none of them rests on colour alone.
  test "the training outcome is a word, coloured only when it is an exception" do
    trained = intake_training_status_text("trained")

    assert_match "Trained", trained
    assert_no_match "text-error", trained
    assert_match "fa-check", trained

    none = intake_training_status_text("none")

    assert_match "No training sign-up", none
    assert_match "text-error", none
    assert_match "fa-ban", none
  end
end
