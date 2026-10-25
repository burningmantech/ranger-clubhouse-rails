# frozen_string_literal: true

require "test_helper"

# The rules the picker table and the printed form both read off an Entry:
# which sign-ups count, what makes an issue, and how far the notes reach back.
class AlphaAcceptanceSheetsTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 25, 12, 0, 0)
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)
    @training_position = Position.create!(id: Position::TRAINING, title: "In-Person Training",
                                          type: Position::TYPE_TRAINING, active: true)

    @slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                        description: "Alpha Walk Wednesday Day")
    @training_slot = create_slot(@training_position, begins: Time.zone.local(YEAR, 6, 14, 9, 0, 0),
                                 description: "Bay Area - Berkeley")

    @alpha = create_person("Zebra", status: Person::ALPHA)
    @author = create_person("Scribe")
  end

  teardown do
    Current.reset
    travel_back
  end

  def entry_for(person, year: YEAR)
    AlphaAcceptanceSheets.for_year(year).find { |entry| entry.person.id == person.id }
  end

  test "the roster is current Alphas, sorted case-insensitively by callsign" do
    create_person("apple", status: Person::ALPHA)
    create_person("Banana", status: Person::ALPHA)
    create_person("NotAnAlpha", status: Person::PROSPECTIVE)

    # Relative order, because the fixtures carry an Alpha of their own.
    callsigns = AlphaAcceptanceSheets.for_year(YEAR).map { |entry| entry.person.callsign }
    assert_equal ["apple", "Banana", "Zebra"], callsigns & ["apple", "Banana", "Zebra"]
    refute_includes callsigns, "NotAnAlpha"
  end

  test "an Alpha with no training and no shift reports all three issues" do
    assert_equal [AlphaAcceptanceSheets::NO_TRAINING,
                  AlphaAcceptanceSheets::NOT_TRAINED,
                  AlphaAcceptanceSheets::NO_ALPHA_SHIFT],
                 entry_for(@alpha).issues
  end

  test "passing this year's training and holding a shift clears every issue" do
    PersonSlot.create!(person_id: @alpha.id, slot_id: @training_slot.id)
    TraineeStatus.create!(person_id: @alpha.id, slot_id: @training_slot.id, status: TraineeStatus::STATUS_PASSED)
    PersonSlot.create!(person_id: @alpha.id, slot_id: @slot.id)

    entry = entry_for(@alpha)
    assert_empty entry.issues
    assert entry.trained
  end

  test "an earlier year's pass leaves the Alpha untrained for this one" do
    old_slot = create_slot(@training_position, begins: Time.zone.local(YEAR - 1, 6, 14, 9, 0, 0),
                           description: "Bay Area - Last Year")
    PersonSlot.create!(person_id: @alpha.id, slot_id: old_slot.id)
    TraineeStatus.create!(person_id: @alpha.id, slot_id: old_slot.id, status: TraineeStatus::STATUS_PASSED)

    entry = entry_for(@alpha)
    refute entry.trained
    assert_includes entry.issues, AlphaAcceptanceSheets::NOT_TRAINED
    refute_includes entry.issues, AlphaAcceptanceSheets::NO_TRAINING,
                    "an earlier session is still a training sign-up"
  end

  test "only passed sessions reach the training notes box" do
    passed_slot = create_slot(@training_position, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0),
                              description: "Passed one")
    [@training_slot, passed_slot].each do |slot|
      PersonSlot.create!(person_id: @alpha.id, slot_id: slot.id)
    end
    TraineeStatus.create!(person_id: @alpha.id, slot_id: @training_slot.id, status: TraineeStatus::STATUS_NOT_PASSED)
    TraineeStatus.create!(person_id: @alpha.id, slot_id: passed_slot.id, status: TraineeStatus::STATUS_PASSED)

    entry = entry_for(@alpha)
    assert_equal 2, entry.trainings.size
    assert_equal ["Passed one"], entry.passed_trainings.map(&:slot_description)
  end

  test "an Alpha shift from another year is not this year's sign-up" do
    other_year = create_slot(@alpha_position, begins: Time.zone.local(YEAR - 1, 8, 26, 8, 0, 0),
                             description: "Alpha Walk Last Year")
    PersonSlot.create!(person_id: @alpha.id, slot_id: other_year.id)

    assert_empty entry_for(@alpha).alpha_slots
    assert_includes entry_for(@alpha).issues, AlphaAcceptanceSheets::NO_ALPHA_SHIFT
  end

  test "an inactive Alpha shift still counts as a sign-up" do
    @slot.update!(active: false)
    PersonSlot.create!(person_id: @alpha.id, slot_id: @slot.id)

    refute_includes entry_for(@alpha).issues, AlphaAcceptanceSheets::NO_ALPHA_SHIFT
  end

  test "the VC and Mentor teams are built, and no other team's notes are loaded" do
    PersonIntake.create!(person_id: @alpha.id, year: YEAR,
                         vc_rank: Intake::ABOVE_AVERAGE, mentor_rank: Intake::BELOW_AVERAGE)
    PersonIntakeNote.create!(person_source_id: @author.id, person_id: @alpha.id, year: YEAR, type: "vc", note: "vc note")
    PersonIntakeNote.create!(person_source_id: @author.id, person_id: @alpha.id, year: YEAR, type: "mentor", note: "mentor note")
    PersonIntakeNote.create!(person_source_id: @author.id, person_id: @alpha.id, year: YEAR, type: "rrn", note: "rrn note")

    entry = entry_for(@alpha)
    assert_equal ["vc note"], entry.vc_team.flat_map { |y| y[:notes].map(&:note) }
    assert_equal ["mentor note"], entry.mentor_team.flat_map { |y| y[:notes].map(&:note) }
    assert_equal Intake::ABOVE_AVERAGE, entry.vc_team.first[:rank]
    assert_equal Intake::BELOW_AVERAGE, entry.mentor_team.first[:rank]
  end

  test "log notes never reach the form" do
    PersonIntakeNote.create!(person_source_id: @author.id, person_id: @alpha.id, year: YEAR, type: "vc",
                             note: "rank changed", is_log: true)
    PersonIntakeNote.create!(person_source_id: @author.id, person_id: @alpha.id, year: YEAR, type: "vc", note: "real note")

    assert_equal ["real note"], entry_for(@alpha).vc_team.flat_map { |y| y[:notes].map(&:note) }
  end

  test "notes from after the page's year are left out" do
    PersonIntakeNote.create!(person_source_id: @author.id, person_id: @alpha.id, year: YEAR, type: "vc", note: "this year")
    PersonIntakeNote.create!(person_source_id: @author.id, person_id: @alpha.id, year: YEAR + 1, type: "vc", note: "next year")

    assert_equal ["this year"], entry_for(@alpha).vc_team.flat_map { |y| y[:notes].map(&:note) }
  end

  test "prior mentors come back most recent first" do
    older = create_person("Quartz")
    newer = create_person("Moonbeam")
    PersonMentor.create!(person_id: @alpha.id, mentor_id: older.id, mentor_year: YEAR - 3,
                         status: PersonMentor::STATUS_BONK)
    PersonMentor.create!(person_id: @alpha.id, mentor_id: newer.id, mentor_year: YEAR - 1,
                         status: PersonMentor::STATUS_PASS)

    years = entry_for(@alpha).mentor_years
    assert_equal [YEAR - 1, YEAR - 3], years.map { |history| history[:year] }
    assert_equal ["Moonbeam"], years.first[:mentors]
    assert_equal PersonMentor::STATUS_PASS, years.first[:status]
  end

  test "narrowing to a selection keeps only current Alphas" do
    other = create_person("Yak", status: Person::ALPHA)
    prospective = create_person("Xylo", status: Person::PROSPECTIVE)

    entries = AlphaAcceptanceSheets.for_year(YEAR, person_ids: [@alpha.id, other.id, prospective.id])
    assert_equal ["Yak", "Zebra"], entries.map { |entry| entry.person.callsign }
  end
end
