# frozen_string_literal: true

require "test_helper"

class EventStatsReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper

  # Clear of the timesheet fixtures, which occupy 2023-2025, and above the 2010
  # floor. travel_to makes it the current year so nothing reads as the future.
  YEAR = 2031

  setup do
    Current.reset
    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    @ranger = person(:active_ranger)
    @alpha = person(:alpha_ranger)
    @other_alpha = person(:prospective_ranger)
    @trainer = person(:echelon_ranger)

    @dirt = positions(:ood_position)
    @alpha_position = create_position(Position::ALPHA, "Alpha", Position::TYPE_MENTORING)
    @training = create_position(Position::TRAINING, "Training", Position::TYPE_TRAINING)
    @trainer_position = create_position(Position::TRAINER, "Trainer", Position::TYPE_TRAINING)
    @art = create_position(Position::GREEN_DOT_TRAINING, "Green Dot Training",
                           Position::TYPE_TRAINING)
  end

  teardown do
    travel_back
    Current.reset
  end

  # --- factories ---------------------------------------------------------

  # The positions this report turns on carry fixed ids app-wide, and the
  # fixtures have none of them.
  def create_position(id, title, type)
    Position.create!(id:, title:, type:, active: true, count_hours: true)
  end

  # additional_notes is not optional: Timesheet#is_reason_provided? rejects an
  # entry that arrives with neither a user note nor a reason.
  def create_entry!(person:, position: @dirt, on_duty: @now)
    was = Current.person
    Current.person = person
    Timesheet.create!(person:, position:, on_duty:, off_duty: on_duty + 6.hours,
                      additional_notes: "Signed in at the window")
  ensure
    Current.person = was
  end

  def sign_up!(person, position, year: YEAR)
    slot = create_slot(position, begins: Time.zone.local(year, 8, 26, 18, 0, 0))
    PersonSlot.create!(person:, slot:)
    slot
  end

  def mint!(person, year: YEAR)
    PersonStatus.create!(person_id: person.id, old_status: Person::ALPHA,
                         new_status: Person::ACTIVE, reason: "passed",
                         person_source_id: @ranger.id,
                         created_at: Time.zone.local(year, 9, 1, 12, 0, 0))
  end

  def pass_training!(person, position, year: YEAR)
    slot = create_slot(position, begins: Time.zone.local(year, 8, 1, 9, 0, 0))
    TraineeStatus.create!(person:, slot:, status: TraineeStatus::STATUS_PASSED)
    slot
  end

  # A trainer's attendance names two slots: the session taught (slot_id) and the
  # trainer's own sign-up (trainer_slot_id).
  def teach_training!(person, position, year: YEAR)
    session = create_slot(position, begins: Time.zone.local(year, 8, 2, 9, 0, 0))
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(year, 8, 2, 8, 0, 0))
    TrainerStatus.create!(person:, slot: session, trainer_slot:,
                          status: TrainerStatus::STATUS_ATTENDED)
    session
  end

  def report(year = YEAR) = EventStatsReport.execute(year:)

  # --- turnout -----------------------------------------------------------

  test "people rangered counts people, not entries, and skips Alpha and training" do
    create_entry!(person: @ranger)
    create_entry!(person: @ranger, on_duty: @now + 2.days)
    create_entry!(person: @alpha, position: @alpha_position)
    create_entry!(person: @trainer, position: @training)

    turnout = report.turnout
    assert_equal 1, turnout.people_rangered
    assert_equal 4, turnout.timesheet_entries, "every entry counts toward the total"
  end

  test "sign-up estimates skip Alpha and training shifts" do
    sign_up!(@ranger, @dirt)
    sign_up!(@alpha, @alpha_position)
    sign_up!(@trainer, @training)

    assert_equal 1, report.turnout.estimated_people
  end

  test "the returning estimate drops this year's Alphas" do
    sign_up!(@ranger, @dirt)
    sign_up!(@alpha, @dirt)
    create_entry!(person: @alpha, position: @alpha_position)

    turnout = report.turnout
    assert_equal 2, turnout.estimated_people
    assert_equal 1, turnout.estimated_returning
  end

  test "a Shiny Penny counts only once minted and rangering" do
    create_entry!(person: @alpha, position: @alpha_position)
    create_entry!(person: @alpha)
    mint!(@alpha)

    # Rangered, but became active in some earlier year.
    create_entry!(person: @other_alpha, position: @alpha_position)
    create_entry!(person: @other_alpha)
    mint!(@other_alpha, year: YEAR - 3)

    assert_equal 1, report.turnout.shiny_pennies_rangered
  end

  test "Shiny Pennies who did not ranger is the gap below the passing Alphas" do
    create_entry!(person: @alpha, position: @alpha_position)
    create_entry!(person: @alpha)
    mint!(@alpha)
    PersonMentor.create!(person: @alpha, mentor: @ranger, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)
    PersonMentor.create!(person: @other_alpha, mentor: @ranger, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)

    turnout = report.turnout
    assert_equal 1, turnout.shiny_pennies_rangered
    assert_equal 1, turnout.shiny_pennies_not_rangered
    assert_equal 2, turnout.shiny_pennies_minted
  end

  test "the Shiny Penny gap never goes negative" do
    create_entry!(person: @alpha, position: @alpha_position)
    create_entry!(person: @alpha)
    mint!(@alpha)

    # Rangered and minted, but no mentor record at all, so no one "passed".
    assert_equal 1, report.turnout.shiny_pennies_rangered
    assert_equal 0, report.turnout.shiny_pennies_not_rangered
  end

  test "the on site count answers for the current year only" do
    Person.where(id: @ranger.id).update_all(on_site: true)

    assert_equal 1, report.turnout.on_site
    assert_nil report(YEAR - 1).turnout.on_site,
               "a past year has no honest answer for a live flag"
  end

  # --- alphas ------------------------------------------------------------

  test "alpha outcomes split the people who walked" do
    PersonMentor.create!(person: @alpha, mentor: @ranger, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)
    # A second mentor for the same Alpha: people, not mentor records.
    PersonMentor.create!(person: @alpha, mentor: @trainer, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)
    PersonMentor.create!(person: @other_alpha, mentor: @ranger, mentor_year: YEAR,
                         status: PersonMentor::STATUS_SELF_BONK)
    PersonMentor.create!(person: @trainer, mentor: @ranger, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PENDING)

    alphas = report.alphas
    assert_equal 3, alphas.walked
    assert_equal 1, alphas.passed
    assert_equal 1, alphas.bonked, "a self-bonk is a bonk"
    assert_equal 1, alphas.walking
  end

  test "alpha entries count rows, not people" do
    create_entry!(person: @alpha, position: @alpha_position)
    create_entry!(person: @alpha, position: @alpha_position, on_duty: @now + 1.day)

    assert_equal 2, report.alphas.timesheet_entries
  end

  # --- training ----------------------------------------------------------

  test "a person trained twice in one training is counted once" do
    pass_training!(@ranger, @training)
    pass_training!(@ranger, @training)
    teach_training!(@ranger, @training)

    training = report.trainings.sole
    assert_equal "In-Person Training", training.title
    assert_equal 1, training.passed
    assert_equal 1, training.taught
    assert_equal 1, training.people
  end

  test "teaching a session counts as finishing the training" do
    pass_training!(@ranger, @training)
    teach_training!(@trainer, @training)

    training = report.trainings.sole
    assert_equal 1, training.passed
    assert_equal 1, training.taught
    assert_equal 2, training.people
  end

  test "a failed session is not a finished training" do
    slot = create_slot(@training, begins: Time.zone.local(YEAR, 8, 1, 9, 0, 0))
    TraineeStatus.create!(person: @ranger, slot:, status: TraineeStatus::STATUS_NOT_PASSED)

    assert_empty report.trainings
  end

  test "trainer positions get no row of their own" do
    teach_training!(@trainer, @training)

    assert_equal ["In-Person Training"], report.trainings.map(&:title)
  end

  test "trainings are listed biggest first and the headline counts each person once" do
    pass_training!(@ranger, @training)
    pass_training!(@alpha, @training)
    pass_training!(@ranger, @art)

    result = report
    assert_equal ["In-Person Training", "Green Dot Training"], result.trainings.map(&:title)
    assert_equal [2, 1], result.trainings.map(&:people)
    assert_equal 2, result.people_trained, "the two rows share a person"
    assert_equal [100, 50], result.trainings.map(&:share),
                 "each bar is measured against the biggest training"
  end

  test "another year's sessions stay out" do
    pass_training!(@ranger, @training, year: YEAR - 1)

    assert_empty report.trainings
  end

  test "an inactive session is not counted" do
    slot = create_slot(@training, begins: Time.zone.local(YEAR, 8, 1, 9, 0, 0), active: false)
    TraineeStatus.create!(person: @ranger, slot:, status: TraineeStatus::STATUS_PASSED)

    assert_empty report.trainings
  end

  # --- shares and the empty year -----------------------------------------

  test "shares are whole percents and zero out of zero is zero" do
    assert_equal 50, EventStatsReport.share(1, 2)
    assert_equal 0, EventStatsReport.share(0, 0)
    assert_equal 100, EventStatsReport.share(5, 3), "a share can never exceed the bar"
  end

  test "a year with nothing recorded reports itself empty" do
    assert_predicate report(YEAR - 2), :empty?
  end

  test "a year with sign-ups alone is not empty" do
    sign_up!(@ranger, @dirt)

    assert_not_predicate report, :empty?
  end
end
