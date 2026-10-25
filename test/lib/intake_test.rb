# frozen_string_literal: true

require "test_helper"

# Shared scaffolding for both Intake suites. Slot/PersonSlot/TraineeStatus/
# PersonStatus have no fixture files in this repo (see
# test/lib/scheduling/signup_characterization_test.rb's note on the same), so
# tests build those rows themselves.
module IntakeTestSupport
  include ActiveSupport::Testing::TimeHelpers
  include IntakeTestHelper

  def ensure_position(id, title, type: nil)
    position = Position.find_or_initialize_by(id: id)
    position.assign_attributes(title: title, type: type, active: true)
    position.save!
    position
  end

  def build_slot(position_id:, begins:, ends: begins + 8.hours)
    Slot.create!(
      position_id: position_id, begins: begins, ends: ends,
      max: 10, active: true, timezone: "America/Los_Angeles"
    )
  end
end

# Unit tests for Intake.history_for_person -- see .scratch/unified-flagging/PRD.md
# for the domain background (ranks, teams, black-flag banner, PNV timeline).
#
# prospective_ranger is the PNV used throughout: person_intake.yml/person_intake_note.yml
# give it a rank+note per team across 2023-2026, person_mentor.yml gives it a 2024
# mentor pass, and timesheet.yml gives it a single 2025 Alpha shift.
class IntakeTest < ActiveSupport::TestCase
  include IntakeTestSupport

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset

    ensure_position(Position::ALPHA, "Alpha")
    ensure_position(Position::TRAINING, "In-Person Training", type: Position::TYPE_TRAINING)

    @pnv = person(:prospective_ranger)
  end

  teardown do
    Current.reset
    travel_back
  end

  # ---- personnel_issue ----

  test "personnel_issue is true when the FLAG is in the exact queried year" do
    result = Intake.history_for_person(@pnv, 2026)

    assert result[:personnel_issue]
  end

  test "personnel_issue is false when the FLAG happened in an earlier year than queried" do
    result = Intake.history_for_person(@pnv, 2027)

    assert_not result[:personnel_issue]
    # The per-year pnv_history row for the flagged year still records it.
    row = result[:pnv_history].find { |r| r[:year] == 2026 }
    assert row[:personnel_issue]
  end

  test "personnel_issue is false when queried before the FLAG year, which is excluded entirely" do
    result = Intake.history_for_person(@pnv, 2025)

    assert_not result[:personnel_issue]
    assert_nil result[:pnv_history].find { |r| r[:year] == 2026 }
  end

  # ---- teams ----

  test "teams sorts a team's entries by year ascending and pairs rank with notes" do
    result = Intake.history_for_person(@pnv, 2026)
    personnel = result[:teams]["personnel"]

    assert_equal [2023, 2026], personnel.map { |row| row[:year] }

    year_2023 = personnel.first
    assert_nil year_2023[:rank]
    assert_equal [person_intake_note(:prospective_personnel_note_2023)], year_2023[:notes]
    assert year_2023[:have_notes]

    year_2026 = personnel.last
    assert_equal 4, year_2026[:rank]
    assert_equal [
      person_intake_note(:prospective_personnel_note_2026_a),
      person_intake_note(:prospective_personnel_note_2026_b),
      person_intake_note(:prospective_personnel_rank_change_2026)
    ], year_2026[:notes]
    assert year_2026[:have_notes]
  end

  test "notes for the same year but different teams do not leak across teams" do
    result = Intake.history_for_person(@pnv, 2026)

    rrn_2024 = result[:teams]["rrn"].find { |row| row[:year] == 2024 }
    mentor_2024 = result[:teams]["mentor"].find { |row| row[:year] == 2024 }

    assert_equal 2, rrn_2024[:rank]
    assert_equal [person_intake_note(:prospective_rrn_note_2024)], rrn_2024[:notes]

    assert_equal 1, mentor_2024[:rank]
    assert_equal [person_intake_note(:prospective_mentor_note_2024)], mentor_2024[:notes]
  end

  test "have_notes is false for a year whose only note is a log note" do
    log_note = PersonIntakeNote.record(
      person_id: @pnv.id, year: 2025, type: "mentor",
      note: "rank change [no rank] -> [2]", is_log: true,
      person_source_id: person(:auditor_ranger).id
    )

    result = Intake.history_for_person(@pnv, 2026)
    mentor_2025 = result[:teams]["mentor"].find { |row| row[:year] == 2025 }

    assert_nil mentor_2025[:rank]
    assert_equal [log_note], mentor_2025[:notes]
    assert_not mentor_2025[:have_notes]
  end

  test "rrn_only restricts teams to rrn alone and empties trainings" do
    result = Intake.history_for_person(@pnv, 2026, rrn_only: true)

    assert_equal ["rrn"], result[:teams].keys
    assert_equal [], result[:trainings]
    # personnel_issue is computed independently of rrn_only -- the banner still
    # needs it even in the RRN-restricted view.
    assert result[:personnel_issue]

    rrn = result[:teams]["rrn"].find { |row| row[:year] == 2024 }
    assert_equal 2, rrn[:rank]
  end

  # ---- pnv_history ----

  test "was_auditor reflects the latest status as of that year, not a later change" do
    PersonStatus.create!(
      person_id: @pnv.id, old_status: Person::PROSPECTIVE, new_status: Person::AUDITOR,
      reason: "became an auditor", created_at: Time.zone.local(2022, 3, 1)
    )
    PersonStatus.create!(
      person_id: @pnv.id, old_status: Person::AUDITOR, new_status: Person::PROSPECTIVE,
      reason: "became prospective", created_at: Time.zone.local(2023, 1, 15)
    )

    result = Intake.history_for_person(@pnv, 2026)

    row_2022 = result[:pnv_history].find { |r| r[:year] == 2022 }
    row_2023 = result[:pnv_history].find { |r| r[:year] == 2023 }

    assert row_2022[:was_auditor]
    assert_not row_2023[:was_auditor]
  end

  test "passed_previously is false in the pass year and true starting the year after" do
    result = Intake.history_for_person(@pnv, 2026)

    row_2024 = result[:pnv_history].find { |r| r[:year] == 2024 }
    row_2025 = result[:pnv_history].find { |r| r[:year] == 2025 }
    row_2026 = result[:pnv_history].find { |r| r[:year] == 2026 }

    assert_equal "pass", row_2024[:mentor_status]
    assert_not row_2024[:passed_previously]
    assert row_2025[:passed_previously]
    assert row_2026[:passed_previously]
  end

  test "a repeat pass year is never flagged passed_previously (matches Ember: pass years show their own badge)" do
    # prospective_ranger already passes in 2024; a later pass year must still
    # render via its own mentor badge, not fall through to "active status".
    PersonMentor.create!(person: @pnv, mentor: person(:active_ranger),
                         mentor_year: 2025, status: PersonMentor::STATUS_PASS)

    result = Intake.history_for_person(@pnv, 2026)
    row_2025 = result[:pnv_history].find { |r| r[:year] == 2025 }

    assert_equal "pass", row_2025[:mentor_status]
    assert_not row_2025[:passed_previously], "a year that is itself a pass must not be flagged passed_previously"
  end

  test "have_alpha_shift is true for a year with an Alpha timesheet entry" do
    result = Intake.history_for_person(@pnv, 2026)

    row_2024 = result[:pnv_history].find { |r| r[:year] == 2024 }
    row_2025 = result[:pnv_history].find { |r| r[:year] == 2025 }

    # 2024 (the mentor pass year) has no timesheet or slot signup of its own --
    # confirms the mentor-history path's own have_alpha_shift check (a faithful
    # port of an upstream bug, see Intake.apply_mentor_history) never fires here.
    assert_not row_2024[:have_alpha_shift]
    # 2025 comes from the prospective_ranger_alpha_2025 timesheet fixture.
    assert row_2025[:have_alpha_shift]
  end

  test "have_alpha_shift is true for a year with an Alpha slot signup, surfaced via a training-year touch" do
    training_slot = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(2021, 3, 1, 9, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: training_slot.id)
    TraineeStatus.create!(person_id: @pnv.id, slot_id: training_slot.id, status: TraineeStatus::STATUS_PASSED)

    alpha_slot = build_slot(position_id: Position::ALPHA, begins: Time.zone.local(2021, 8, 25, 10, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: alpha_slot.id)

    result = Intake.history_for_person(@pnv, 2026)
    row_2021 = result[:pnv_history].find { |r| r[:year] == 2021 }

    assert row_2021[:have_alpha_shift]
    assert_equal "pass", row_2021[:training_status]
  end

  test "training_status never downgrades from pass once a session in the year has passed" do
    passed_slot = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(2020, 3, 1, 9, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: passed_slot.id)
    TraineeStatus.create!(person_id: @pnv.id, slot_id: passed_slot.id, status: TraineeStatus::STATUS_PASSED)

    failed_slot = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(2020, 11, 1, 9, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: failed_slot.id)
    TraineeStatus.create!(person_id: @pnv.id, slot_id: failed_slot.id, status: TraineeStatus::STATUS_NOT_PASSED)

    result = Intake.history_for_person(@pnv, 2026)
    row_2020 = result[:pnv_history].find { |r| r[:year] == 2020 }

    assert_equal "pass", row_2020[:training_status]
  end

  test "training_status is pending for a session that has not ended yet" do
    upcoming_slot = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(2026, 8, 25, 9, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: upcoming_slot.id)

    result = Intake.history_for_person(@pnv, 2026)
    row_2026 = result[:pnv_history].find { |r| r[:year] == 2026 }

    assert_equal "pending", row_2026[:training_status]
  end

  test "a year the person taught shows taught, unless they also attended as a trainee that year" do
    ensure_position(Position::TRAINER, "Trainer")
    taught = lambda do |begins|
      TrainerStatus.create!(
        person_id: @pnv.id, status: TrainerStatus::STATUS_ATTENDED,
        slot_id: build_slot(position_id: Position::TRAINING, begins: begins).id,
        trainer_slot_id: build_slot(position_id: Position::TRAINER, begins: begins - 30.minutes).id
      )
    end

    # 2021: taught only.
    taught.call(Time.zone.local(2021, 6, 5, 9, 30, 0))

    # 2020: passed as a trainee AND taught -- the trainee record wins.
    passed_slot = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(2020, 3, 1, 9, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: passed_slot.id)
    TraineeStatus.create!(person_id: @pnv.id, slot_id: passed_slot.id, status: TraineeStatus::STATUS_PASSED)
    taught.call(Time.zone.local(2020, 8, 1, 9, 30, 0))

    rows = Intake.history_for_person(@pnv, 2026)[:pnv_history].index_by { |r| r[:year] }

    assert_equal "taught", rows[2021][:training_status]
    assert_equal "pass", rows[2020][:training_status]
  end

  # ---- no data at all ----

  test "returns an empty-but-well-shaped history for a person with no intake data" do
    result = Intake.history_for_person(person(:retired_ranger), 2026)

    assert_not result[:personnel_issue]
    assert_equal Intake::TEAM_TYPES, result[:teams].keys
    result[:teams].each_value { |team| assert_equal [], team }
    assert_equal [], result[:trainings]
    assert_equal [], result[:pnv_history]
  end
end

# Unit tests for Intake.retrieve_all_for_year -- the VC pipeline page's roster,
# flag gate and summary math. Kept apart from the suite above because roster
# membership needs person_status rows, and those rows would otherwise perturb
# the pnv_history assertions there.
#
# @pnv carries personnel_rank 4 in 2026, vc_rank 3 in 2025, mentor_rank 1 and
# rrn_rank 2 in 2024, so one person exercises every rank. @clean carries no
# marks at all, which is what the only_flagged gate is judged against.
class IntakeRetrieveAllForYearTest < ActiveSupport::TestCase
  include IntakeTestSupport

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset

    ensure_position(Position::ALPHA, "Alpha")
    ensure_position(Position::TRAINING, "In-Person Training", type: Position::TYPE_TRAINING)

    @pnv = person(:prospective_ranger)
    @clean = person(:alpha_ranger)
    place_in_pipeline(@pnv, 2026)
    place_in_pipeline(@clean, 2026)
  end

  teardown do
    Current.reset
    travel_back
  end

  # @pnv (prospective_ranger) carries personnel_rank 4 in 2026, vc_rank 3 in
  # 2025, mentor_rank 1 and rrn_rank 2 in 2024, so one person exercises every
  # rank. Roster membership comes from holding Prospective/Alpha status.

  test "a personnel flag in the viewed year quarantines the person into their own group" do
    summary = summary_for(@pnv, 2026)

    assert_equal :personnel, summary[:group]
    assert summary[:personnel_issue]
    assert_equal 100, summary[:severity_weight], "a raised flag must outrank every rank-based weight"
  end

  test "the flag stops quarantining once an earlier year is viewed" do
    place_in_pipeline(@pnv, 2025)

    summary = summary_for(@pnv, 2025)

    assert_not summary[:personnel_issue]
    assert_equal :flagged, summary[:group], "2025's vc_rank 3 still places them in rank 3/4 or bonk"
  end

  # Upstream severity is 4 > 3 > 1 > 2: Green outranks Normal because it is the
  # more notable signal, so a plain max() on the rank number would be wrong.
  test "worst_rank follows upstream severity order rather than numeric order" do
    assert_equal Intake::ABOVE_AVERAGE, worst_rank_for(mentor_rank: 1, rrn_rank: 2)
    assert_equal Intake::BELOW_AVERAGE, worst_rank_for(mentor_rank: 1, vc_rank: 3)
    assert_equal Intake::FLAG, worst_rank_for(vc_rank: 3, rrn_rank: 4)
  end

  test "the rank strip is ordered worst-first and names each team and year" do
    place_in_pipeline(@pnv, 2025)

    ranks = summary_for(@pnv, 2025)[:ranks]

    # Worst-first by severity, so Green (1) sorts ahead of Normal (2).
    assert_equal [3, 1, 2], ranks.map { |entry| entry[:rank] }
    assert_equal({ year: 2025, rank: 3, team: "vc" }, ranks.first)
  end

  # Equal ranks sort by Intake::TEAM_ORDER, so a row's lead chip names the same
  # team as its gray line and the convert-prospectives cell.
  test "the rank strip breaks a tie by team order" do
    other = person(:alpha_ranger)
    PersonIntake.create!(person_id: other.id, year: 2026,
                         mentor_rank: Intake::BELOW_AVERAGE, vc_rank: Intake::BELOW_AVERAGE)

    tied = summary_for(other, 2026)[:ranks].select { |entry| entry[:rank] == Intake::BELOW_AVERAGE }

    assert_equal %w[vc mentor], tied.map { |entry| entry[:team] }
  ensure
    PersonIntake.where(person_id: other.id, year: 2026).delete_all
  end

  test "the personnel chip is dropped only while the banner is showing it" do
    flagged = summary_for(@pnv, 2026)
    assert flagged[:personnel_issue]
    assert_not flagged[:ranks].any? { |entry| entry[:team] == "personnel" },
               "the quarantine banner already states the flag"
    assert_equal Intake::FLAG, flagged[:worst_rank], "suppressing the chip must not change severity"

    # 2027 keeps the 2026 flag as the latest personnel rank but raises no banner,
    # so the chip is the only thing left saying so.
    place_in_pipeline(@pnv, 2027)
    later = summary_for(@pnv, 2027)
    assert_not later[:personnel_issue]
    assert later[:ranks].any? { |entry| entry[:team] == "personnel" && entry[:rank] == Intake::FLAG }
  end

  test "a self-bonk groups with hard bonks" do
    other = person(:alpha_ranger)
    PersonMentor.create!(person_id: other.id, mentor_id: @pnv.id, mentor_year: 2025,
                         status: PersonMentor::STATUS_SELF_BONK)

    summary = summary_for(other, 2026)

    assert_equal :flagged, summary[:group], "the row shows a red self-bonk chip, so it must not sit in Other"
    assert_equal({ year: 2025, status: PersonMentor::STATUS_SELF_BONK }, summary[:bonk])
  end

  # The row's lead chip shows a current uber-bonk in red
  # (IntakeHelper#intake_lead_kind), so the group must count it too, or a
  # red-chipped person sits in "Other potential Alphas".
  test "an uber-bonk groups with the flagged" do
    other = person(:alpha_ranger)
    assert_equal :other, summary_for(other, 2026)[:group], "calm ranks and no bonk to begin with"

    other.update_column(:status, Person::UBERBONKED)

    assert_equal :flagged, summary_for(other, 2026)[:group]
  end

  # Upstream's mentor lookup ignores the year entirely, and a bonk decides both
  # the flag and the row's group -- clipping it to the viewed year silently
  # demoted people into "Other potential Alphas" on historical views.
  test "a bonk counts on every year's view, including years before it happened" do
    other = person(:alpha_ranger)
    PersonMentor.create!(person_id: other.id, mentor_id: @pnv.id, mentor_year: 2026,
                         status: PersonMentor::STATUS_BONK)
    place_in_pipeline(other, 2025)

    assert_equal 2026, summary_for(other, 2025).dig(:bonk, :year)
    assert_equal 2026, summary_for(other, 2026).dig(:bonk, :year)
  end

  # ---- only_flagged: who the page actually shows ----

  test "the page shows only people carrying an adverse mark" do
    clean = person(:alpha_ranger)

    shown = Intake.retrieve_all_for_year(2026).map { |summary| summary[:person].id }

    assert_includes shown, @pnv.id, "a personnel FLAG is an adverse mark"
    assert_not_includes shown, clean.id, "an unremarkable PNV is not part of the triage list"
  end

  test "a rank of 3 or worse in any past year is an adverse mark" do
    other = person(:alpha_ranger)
    PersonIntake.create!(person_id: other.id, year: 2019, vc_rank: Intake::BELOW_AVERAGE)

    assert_includes flagged_ids(2026), other.id
  end

  test "a green or normal rank is not an adverse mark" do
    other = person(:alpha_ranger)
    PersonIntake.create!(person_id: other.id, year: 2026,
                         mentor_rank: Intake::ABOVE_AVERAGE, rrn_rank: Intake::AVERAGE)

    assert_not_includes flagged_ids(2026), other.id
  end

  test "a self-bonk is an adverse mark" do
    other = person(:alpha_ranger)
    PersonMentor.create!(person_id: other.id, mentor_id: @pnv.id, mentor_year: 2024,
                         status: PersonMentor::STATUS_SELF_BONK)

    assert_includes flagged_ids(2026), other.id
  end

  # Upstream counts a training rank whether or not the session has ended -- a
  # concern recorded mid-session is still a concern.
  test "a training rank of 3 or worse is an adverse mark even before the session ends" do
    other = person(:alpha_ranger)
    slot = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(2026, 8, 25, 9, 0, 0))
    PersonSlot.create!(person_id: other.id, slot_id: slot.id)
    TraineeStatus.create!(person_id: other.id, slot_id: slot.id, rank: Intake::BELOW_AVERAGE)

    assert_not slot.has_ended
    assert_includes flagged_ids(2026), other.id
  end

  # Anything short of a pass on an ended session reports "not passed" -- a
  # no-show as much as a fail -- and never the green "trained" chip.
  test "an ended session that was failed reports not passed, never trained" do
    slot = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(2026, 3, 1, 9, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: slot.id)
    row = TraineeStatus.create!(person_id: @pnv.id, slot_id: slot.id,
                                status: TraineeStatus::STATUS_NOT_PASSED, rank: 3)

    assert_equal "not passed", summary_for(@pnv, 2026)[:training_status]

    row.update!(status: TraineeStatus::STATUS_NO_SHOW)
    assert_equal "not passed", summary_for(@pnv, 2026)[:training_status]
  end

  test "a passed session in the same year wins over a failed one" do
    failed = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(2026, 3, 1, 9, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: failed.id)
    TraineeStatus.create!(person_id: @pnv.id, slot_id: failed.id, status: TraineeStatus::STATUS_NOT_PASSED)

    passed = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(2026, 3, 15, 9, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: passed.id)
    TraineeStatus.create!(person_id: @pnv.id, slot_id: passed.id, status: TraineeStatus::STATUS_PASSED)

    assert_equal "trained", summary_for(@pnv, 2026)[:training_status]
  end

  test "training status is scoped to the viewed year, not carried forward" do
    slot = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(2025, 3, 1, 9, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: slot.id)
    TraineeStatus.create!(person_id: @pnv.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)
    place_in_pipeline(@pnv, 2025)

    assert_equal "trained", summary_for(@pnv, 2025)[:training_status]
    assert_equal "none", summary_for(@pnv, 2026)[:training_status], "2025's pass says nothing about 2026"
  end

  test "note pills carry each team's latest note date" do
    pill = summary_for(@pnv, 2026)[:note_teams].find { |entry| entry[:team] == "vc" }

    assert_equal 3, pill[:rank], "the pill is coloured by that team's latest rank"
    assert_equal 2025, pill[:latest_at].year
  end

  # created_at is nullable on person_intake_note; one note without it is
  # passed over, not compared with the others' times.
  test "a note with no timestamp is passed over for its team's latest" do
    person_intake_note(:prospective_personnel_note_2026_a).update_column(:created_at, nil)

    pill = summary_for(@pnv, 2026)[:note_teams].find { |entry| entry[:team] == "personnel" }

    assert_equal person_intake_note(:prospective_personnel_note_2026_b).created_at, pill[:latest_at]
  end

  test "log notes never raise a note pill on their own" do
    other = person(:alpha_ranger)
    PersonIntakeNote.create!(person_id: other.id, year: 2026, type: "vc", is_log: true,
                            note: "rank changed", person_source_id: @pnv.id)

    assert_empty summary_for(other, 2026)[:note_teams]
  end

  test "groups render personnel first, then flagged, then everyone else" do
    groups = Intake.retrieve_all_for_year(2026).map { |summary| summary[:group] }

    assert_equal groups.uniq, groups.uniq.sort_by { |group| Intake::GROUP_ORDER.index(group) },
                 "summaries must arrive already ordered by group"
  end

  private

  # The summary-math tests are about one person's numbers, not about who the
  # page chooses to show, so they look past the only_flagged gate. The gate has
  # its own tests below.
  def summary_for(target, year)
    Intake.retrieve_all_for_year(year, only_flagged: false)
          .find { |summary| summary[:person].id == target.id } ||
      flunk("#{target.callsign} is not in the #{year} pipeline roster")
  end

  def flagged_ids(year)
    Intake.retrieve_all_for_year(year).map { |summary| summary[:person].id }
  end

  # Ranks are read from the latest year that set them, so one row is enough.
  def worst_rank_for(**ranks)
    other = person(:alpha_ranger)
    PersonIntake.create!(person_id: other.id, year: 2026, **ranks)
    worst = summary_for(other, 2026)[:worst_rank]
    PersonIntake.where(person_id: other.id, year: 2026).delete_all
    worst
  end
end

# Unit tests for Intake.retrieve_post_season_class -- the five viewed-year
# mentor facts /mentoring/post-season-summary adds on top of the shared
# summary, and the roster it adds them to.
#
# Kept apart from the suite above for the same reason that one is: roster
# membership needs person_status rows.
class IntakeRetrievePostSeasonClassTest < ActiveSupport::TestCase
  include IntakeTestSupport

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 10, 1, 12, 0, 0)
    Current.reset

    ensure_position(Position::ALPHA, "Alpha")
    ensure_position(Position::TRAINING, "In-Person Training", type: Position::TYPE_TRAINING)

    @shift = build_slot(position_id: Position::ALPHA, begins: Time.zone.local(YEAR, 8, 20, 17, 0, 0))
    @old_shift = build_slot(position_id: Position::ALPHA, begins: Time.zone.local(YEAR - 1, 8, 20, 17, 0, 0))

    @pnv = person(:prospective_ranger)
    @mentor = person(:echelon_ranger)
    place_in_pipeline(@pnv, YEAR)
  end

  teardown do
    Current.reset
    travel_back
  end

  # The distinguishing fact of the page: upstream requests mentor/mentees
  # WITHOUT exclude_bonks, so somebody who washed out during the year stays.
  test "someone who washed out during the year is kept on the roster" do
    place_in_pipeline(@pnv, YEAR, new_status: Person::BONKED)

    assert_includes roster_ids, @pnv.id
    assert_not_includes Intake.retrieve_year_class(YEAR).map { |s| s[:person].id }, @pnv.id
  end

  test "the roster is not narrowed to people carrying an adverse mark" do
    clean = person(:alpha_ranger)
    place_in_pipeline(clean, YEAR)

    assert_includes roster_ids, clean.id
  end

  test "mentor_status and mentors come from the viewed year" do
    PersonMentor.create!(person_id: @pnv.id, mentor_id: @mentor.id, mentor_year: YEAR,
                         status: PersonMentor::STATUS_BONK)

    summary = summary_for(@pnv)

    assert_equal PersonMentor::STATUS_BONK, summary[:mentor_status]
    assert_equal [@mentor.callsign], summary[:mentors].map { |m| m[:callsign] }
  end

  # The fixtures give this person a 2024 mentor pass, which must not read as
  # this year's verdict.
  test "another year's mentorship is not read as the viewed year's" do
    summary = summary_for(@pnv)

    assert_equal PersonMentor::STATUS_PENDING, summary[:mentor_status]
    assert_empty summary[:mentors]
  end

  test "signed_up is true only for an alpha sign-up in the viewed year" do
    PersonSlot.create!(person_id: @pnv.id, slot_id: @old_shift.id)

    assert_not summary_for(@pnv)[:signed_up]

    PersonSlot.create!(person_id: @pnv.id, slot_id: @shift.id)

    assert summary_for(@pnv)[:signed_up]
  end

  # Only Alpha shifts count. A training session in the same year is a sign-up
  # too, and reading it as one would tell a mentor somebody walked.
  test "a sign-up for another position in the viewed year does not count" do
    training = build_slot(position_id: Position::TRAINING, begins: Time.zone.local(YEAR, 3, 1, 9, 0, 0))
    PersonSlot.create!(person_id: @pnv.id, slot_id: training.id)

    assert_not summary_for(@pnv)[:signed_up]
  end

  # The rank strip on the row is the latest per team across every year; this
  # one is the viewed year alone, which is what splits the two sections.
  test "mentor_rank is the viewed year's rank, not the latest one" do
    # The fixtures already rank this person in 2023-2026; cleared so the two
    # rows below are the only ones the assertions can be reading.
    PersonIntake.where(person_id: @pnv.id).delete_all
    PersonIntake.create!(person_id: @pnv.id, year: YEAR - 2, mentor_rank: Intake::FLAG)

    assert_equal 0, summary_for(@pnv)[:mentor_rank]

    PersonIntake.create!(person_id: @pnv.id, year: YEAR, mentor_rank: Intake::BELOW_AVERAGE)

    assert_equal Intake::BELOW_AVERAGE, summary_for(@pnv)[:mentor_rank]
  end

  test "mentor_notes counts only this year's non-log mentor notes" do
    assert_not summary_for(@pnv)[:mentor_notes]

    PersonIntakeNote.create!(person_id: @pnv.id, year: YEAR, type: "mentor", is_log: true,
                             note: "Logged.", person_source_id: @mentor.id)

    assert_not summary_for(@pnv)[:mentor_notes], "a log note is not somebody having written something"

    PersonIntakeNote.create!(person_id: @pnv.id, year: YEAR, type: "vc",
                             note: "VC wrote this.", person_source_id: @mentor.id)

    assert_not summary_for(@pnv)[:mentor_notes], "another team's note is not a mentor note"

    PersonIntakeNote.create!(person_id: @pnv.id, year: YEAR, type: "mentor",
                             note: "Strong walk.", person_source_id: @mentor.id)

    assert summary_for(@pnv)[:mentor_notes]
  end

  test "an empty class is returned without touching the extra queries" do
    assert_empty Intake.retrieve_post_season_class(1999)
  end

  private

  def roster_ids
    Intake.retrieve_post_season_class(YEAR).map { |summary| summary[:person].id }
  end

  def summary_for(target, year = YEAR)
    Intake.retrieve_post_season_class(year)
          .find { |summary| summary[:person].id == target.id } ||
      flunk("#{target.callsign} is not in the #{year} class")
  end
end

# Unit tests for Intake.retrieve_recorded_for_year -- /people/unified-flagging's
# roster: everyone the intake teams touched in the year, whatever their status,
# and the year's own facts each summary carries for that page's filters and
# export. No person_status rows are needed: being written about is what lists
# a person.
class IntakeRetrieveRecordedForYearTest < ActiveSupport::TestCase
  include IntakeTestSupport

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 16, 12, 0, 0)
    Current.reset

    ensure_position(Position::ALPHA, "Alpha")
    ensure_position(Position::TRAINING, "In-Person Training", type: Position::TYPE_TRAINING)

    @pnv = person(:prospective_ranger)
  end

  teardown do
    Current.reset
    travel_back
  end

  # The fixtures: @pnv's 2026 flag and Personnel notes, past_prospective_ranger's
  # one 2026 Personnel note, ranger_with_custom_gender's 2024 bonk.
  test "whoever was noted, ranked, flagged or bonked in the year is listed, and no one else" do
    assert_equal [person(:past_prospective_ranger).id, @pnv.id].sort, recorded_ids(YEAR).sort

    assert_includes recorded_ids(2024), person(:ranger_with_custom_gender).id
    assert_not_includes recorded_ids(2024), person(:past_prospective_ranger).id
  end

  test "any status is listed, and a log entry lists no one" do
    ranger = person(:active_ranger)
    PersonIntakeNote.create!(person_id: ranger.id, year: YEAR, type: "vc", is_log: true,
                             note: "rank change", person_source_id: @pnv.id)

    assert_not_includes recorded_ids(YEAR), ranger.id

    PersonIntakeNote.create!(person_id: ranger.id, year: YEAR, type: "personnel",
                             note: "Checked in at the gate.", person_source_id: @pnv.id)

    assert_includes recorded_ids(YEAR), ranger.id
  end

  test "a normal rank alone lists someone, and is the year's only fact" do
    ranger = person(:active_ranger)
    PersonIntake.create!(person_id: ranger.id, year: YEAR, vc_rank: Intake::AVERAGE)

    summary = recorded_summary(ranger, YEAR)

    assert_equal({ "vc" => [Intake::AVERAGE] }, summary[:year_ranks])
    assert_empty summary[:year_notes]
    assert_nil summary[:year_bonk]
    assert_equal :other, summary[:group]
  end

  # A session that has ended: the pane shows a trainer's notes and rank only
  # once it has.
  test "a trainer's note and rank on a session that has ended list someone under Training" do
    ranger = person(:alpha_ranger)
    slot = train(ranger, on: Time.zone.local(YEAR, 3, 14, 9, 0, 0), rank: Intake::BELOW_AVERAGE)
    note = TraineeNote.create!(person_id: ranger.id, slot_id: slot.id, note: "Quiet on the radio.",
                               person_source_id: @pnv.id)

    summary = recorded_summary(ranger, YEAR)

    assert_equal({ "training" => [Intake::BELOW_AVERAGE] }, summary[:year_ranks])
    assert_equal [{ team: "training", latest_at: note.reload.created_at }], summary[:year_notes]
  end

  # What the pane cannot show lists no one: _history holds an upcoming
  # session's notes and rank back, and the training history reads a session
  # only through the person's sign-up, which removing them deletes.
  test "a trainer's note or rank on a session not yet over lists no one" do
    ranger = person(:alpha_ranger)
    slot = train(ranger, on: Time.zone.local(YEAR, 8, 25, 9, 0, 0), rank: Intake::BELOW_AVERAGE)
    TraineeNote.create!(person_id: ranger.id, slot_id: slot.id, note: "Early word.", person_source_id: @pnv.id)

    assert_not_includes recorded_ids(YEAR), ranger.id
  end

  test "a trainer's note or rank on a session the person was removed from lists no one" do
    ranger = person(:alpha_ranger)
    slot = train(ranger, on: Time.zone.local(YEAR, 3, 14, 9, 0, 0), rank: Intake::BELOW_AVERAGE)
    TraineeNote.create!(person_id: ranger.id, slot_id: slot.id, note: "Left early.", person_source_id: @pnv.id)
    PersonSlot.where(person_id: ranger.id, slot_id: slot.id).delete_all

    assert_not_includes recorded_ids(YEAR), ranger.id
  end

  # A retake year ranks two sessions: the filter and the export read both,
  # while the line, like every pipeline page's, keeps the latest.
  test "a retake year keeps every training rank, in session order" do
    ranger = person(:alpha_ranger)
    train(ranger, on: Time.zone.local(YEAR, 3, 7, 9, 0, 0), rank: Intake::BELOW_AVERAGE)
    train(ranger, on: Time.zone.local(YEAR, 3, 21, 9, 0, 0), rank: Intake::ABOVE_AVERAGE)

    summary = recorded_summary(ranger, YEAR)

    assert_equal({ "training" => [Intake::BELOW_AVERAGE, Intake::ABOVE_AVERAGE] }, summary[:year_ranks])
    assert_equal Intake::ABOVE_AVERAGE, summary[:ranks].find { |entry| entry[:team] == "training" }[:rank]
  end

  test "a bonk in the year lists someone, with the verdict" do
    ranger = person(:alpha_ranger)
    PersonMentor.create!(person_id: ranger.id, mentor_id: @pnv.id, mentor_year: YEAR,
                         status: PersonMentor::STATUS_SELF_BONK)

    assert_equal PersonMentor::STATUS_SELF_BONK, recorded_summary(ranger, YEAR)[:year_bonk]
  end

  # Two mentors who disagree, written in the order that used to win: a bonk
  # outranks a self-bonk (PersonMentor::VERDICT_PRECEDENCE) whichever row the
  # database hands back last.
  test "a year's disagreeing verdicts resolve by verdict precedence" do
    ranger = person(:alpha_ranger)
    PersonMentor.create!(person_id: ranger.id, mentor_id: @pnv.id, mentor_year: YEAR,
                         status: PersonMentor::STATUS_BONK)
    PersonMentor.create!(person_id: ranger.id, mentor_id: person(:echelon_ranger).id, mentor_year: YEAR,
                         status: PersonMentor::STATUS_SELF_BONK)

    assert_equal PersonMentor::STATUS_BONK, recorded_summary(ranger, YEAR)[:year_bonk]
  end

  # Training is a pipeline question. A Ranger listed for a Personnel note owes
  # no sign-up, so their training status is nil -- the line says nothing, the
  # filter and the export leave it out -- unless they had a session that year
  # or were in the year's pipeline.
  test "a training status applies only to the year's pipeline or a session that year" do
    ranger = person(:active_ranger)
    PersonIntakeNote.create!(person_id: ranger.id, year: YEAR, type: "personnel",
                             note: "Checked in at the gate.", person_source_id: @pnv.id)
    past = person(:past_prospective_ranger)

    assert_nil recorded_summary(ranger, YEAR)[:training_status]
    assert_nil recorded_summary(past, YEAR)[:training_status]
    assert_equal "none", recorded_summary(@pnv, YEAR)[:training_status], "a Prospective owes a sign-up"

    place_in_pipeline(past, YEAR)

    assert_equal "none", recorded_summary(past, YEAR)[:training_status], "so did a Prospective of that year"

    train(ranger, on: Time.zone.local(YEAR, 3, 14, 9, 0, 0))

    assert_equal "not passed", recorded_summary(ranger, YEAR)[:training_status]
  end

  # A review pane asks about one person and gets that person alone, if listed.
  test "a caller asking about some people gets only those" do
    only = ->(target) { Intake.retrieve_recorded_for_year(YEAR, person_ids: [target.id]).map { |s| s[:person].id } }

    assert_equal [@pnv.id], only.call(@pnv)
    assert_empty only.call(person(:active_ranger))
  end

  # The year's facts are the year's alone; the shared side of the summary
  # keeps reading the history to date, as on every pipeline page.
  test "the year's facts stop at the year while the chips keep the history" do
    summary = recorded_summary(@pnv, YEAR)

    assert_equal({ "personnel" => [Intake::FLAG] }, summary[:year_ranks])
    assert_equal [{ team: "personnel", latest_at: person_intake_note(:prospective_personnel_note_2026_b).created_at }],
                 summary[:year_notes]
    assert_nil summary[:year_bonk]
    assert summary[:personnel_issue]
    assert_includes summary[:ranks].map { |entry| entry.slice(:team, :year) }, { team: "vc", year: 2025 }
  end

  private

  def recorded_ids(year)
    Intake.retrieve_recorded_for_year(year).map { |summary| summary[:person].id }
  end

  def recorded_summary(target, year)
    Intake.retrieve_recorded_for_year(year).find { |summary| summary[:person].id == target.id } ||
      flunk("#{target.callsign} is not listed for #{year}")
  end

  # One In-Person Training session `person` signed up for -- over by the
  # suite's clock unless `on` is still ahead of it -- with a trainer's rank
  # when one is given.
  def train(person, on:, rank: nil)
    slot = build_slot(position_id: Position::TRAINING, begins: on)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
    TraineeStatus.create!(person_id: person.id, slot_id: slot.id, rank:) if rank
    slot
  end
end
