# frozen_string_literal: true

require "test_helper"

# The scheduled Shift Lead Report: the overlap window, the three rosters, the
# Green Dot rules, the sort, and the below-minimum list.
class ShiftLeadReportTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2025
  # The window under test: noon to six.
  SHIFT_START = Time.zone.local(YEAR, 8, 27, 12, 0, 0)
  SHIFT_DURATION = 6.hours.to_i

  setup do
    travel_to Time.zone.local(YEAR, 8, 27, 12, 30, 0)
    Rails.cache.clear
    Current.reset

    @dirt = create_position(Position::DIRT, "Dirt", short_title: "Dirt")
    @penny = create_position(Position::DIRT_SHINY_PENNY, "Dirt - Shiny Penny", short_title: "Penny")
    @green_dot = create_position(Position::DIRT_GREEN_DOT, "Dirt - Green Dot", short_title: "GD",
                                 on_sl_report: true)
    @mentee = create_position(Position::GREEN_DOT_MENTEE, "Green Dot Mentee", short_title: "GDMnte")
    @troubleshooter = create_position(Position::TROUBLESHOOTER, "Troubleshooter", short_title: "TS",
                                      on_sl_report: true)
    @ood = create_position(Position::OOD, "Operator on Duty", short_title: "OOD",
                           type: Position::TYPE_COMMAND, on_sl_report: true)
    @intercept = create_position(Position::INTERCEPT, "Intercept", short_title: "Int")
    @gd_training = create_position(Position::GREEN_DOT_TRAINING, "Green Dot Training",
                                   type: Position::TYPE_TRAINING)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- the overlap window ---

  test "a shift spanning the whole window is included" do
    sign_up(create_person("Spanner"), slot_over(11.hours, 19.hours))

    assert_equal ["Spanner"], report.dirt.map(&:callsign)
  end

  test "a shift starting within the hour before the window is included" do
    sign_up(create_person("Early"), slot_over(11.5.hours, 17.hours))

    assert_equal ["Early"], report.dirt.map(&:callsign)
  end

  # 45 minutes past the start is the line: a shift ending half an hour in is
  # somebody else's shift, not this one's coverage.
  test "a shift ending less than 45 minutes into the window is excluded" do
    sign_up(create_person("Leaving"), slot_over(6.hours, 12.5.hours))

    assert_empty report.dirt
  end

  test "a shift ending exactly 45 minutes into the window is included" do
    sign_up(create_person("Staying"), slot_over(6.hours, 12.75.hours))

    assert_equal ["Staying"], report.dirt.map(&:callsign)
  end

  test "a shift starting in the window's last hour is excluded" do
    sign_up(create_person("Relief"), slot_over(17.5.hours, 23.5.hours))

    assert_empty report.dirt
  end

  # Starting inside the leading hour is not enough on its own: a shift that
  # began at 11:15 and ended at 11:45 was over before this window opened.
  test "a shift that started in the leading hour but already ended is excluded" do
    sign_up(create_person("Gone"), slot_over(11.25.hours, 11.75.hours))

    assert_empty report.dirt
  end

  test "shifts outside the window entirely are excluded" do
    sign_up(create_person("Before"), slot_over(4.hours, 10.hours))
    sign_up(create_person("After"), slot_over(19.hours, 23.hours))

    assert_empty report.dirt
  end

  # --- the three rosters ---

  test "each roster draws from its own positions" do
    sign_up(create_person("Dusty"), slot_over(12.hours, 18.hours))
    sign_up(create_person("Khaki"), slot_over(12.hours, 18.hours, position: @ood))
    sign_up(create_person("Cutter"), slot_over(12.hours, 18.hours, position: @intercept))

    result = report

    assert_equal ["Dusty"], result.dirt.map(&:callsign)
    assert_equal ["Khaki"], result.command.map(&:callsign)
    assert_equal ["Cutter"], result.special.map(&:callsign)
  end

  test "a row carries the person's shift, not the window" do
    sign_up(create_person("Dusty"), slot_over(11.5.hours, 17.hours))

    row = report.dirt.sole

    assert_equal SHIFT_START - 30.minutes, row.begins
    assert_equal SHIFT_START + 5.hours, row.ends
  end

  # The roster prints clock times only, so a shift reaching into another day is
  # marked as such.
  test "a shift crossing midnight is marked" do
    sign_up(create_person("Graveyard"), slot_over(-1.hours, 13.hours))

    row = report.dirt.sole

    assert row.begins_day_before
    assert_not row.ends_day_after
  end

  # The marker says which side of midnight, not merely "a different date": the
  # leading hour of an evening window reaches past midnight, so a shift starting
  # tomorrow must not read as having started yesterday.
  test "a shift starting the next day is not marked as the day before" do
    sign_up(create_person("Tomorrow"), evening_report_slot)

    row = evening_report.dirt.sole

    assert_not row.begins_day_before
    assert row.ends_day_after
  end

  # --- the sort ---

  test "Green Dot lines sort above dirt and Shiny Pennies sort last" do
    sign_up(create_person("Penny", years: [YEAR]), slot_over(12.hours, 18.hours, position: @penny))
    sign_up(create_person("Dusty", years: [2019, YEAR]), slot_over(12.hours, 18.hours))
    sign_up(create_person("Verde", years: [2018, 2019]), slot_over(12.hours, 18.hours, position: @green_dot))

    assert_equal %w[Verde Dusty Penny], report.dirt.map(&:callsign)
  end

  test "within a position the longest-serving Ranger sorts first" do
    sign_up(create_person("Sprout", years: [YEAR]), slot_over(12.hours, 18.hours))
    sign_up(create_person("Elder", years: (2010..2024).to_a), slot_over(12.hours, 18.hours))

    assert_equal %w[Elder Sprout], report.dirt.map(&:callsign)
  end

  test "an even match falls back to callsign so the order is fixed" do
    sign_up(create_person("Zulu"), slot_over(12.hours, 18.hours))
    sign_up(create_person("Alfa"), slot_over(12.hours, 18.hours))

    assert_equal %w[Alfa Zulu], report.dirt.map(&:callsign)
  end

  # --- Green Dots ---

  test "a Green Dot who passed training this year is a qualified Green Dot" do
    person = create_person("Verde")
    hold_position(person, @green_dot)
    pass_green_dot_training(person)
    sign_up(person, slot_over(12.hours, 18.hours, position: @green_dot))

    row = report.dirt.sole

    assert row.green_dot
    assert_includes row.positions, "GD"
  end

  # Reading "GD" beside a name is reading a promise the Ranger cannot keep.
  test "a Green Dot who has not passed training loses the chip and the listing" do
    person = create_person("Untrained")
    hold_position(person, @green_dot)
    sign_up(person, slot_over(12.hours, 18.hours, position: @green_dot))

    row = report.dirt.sole

    assert_not row.green_dot
    assert_not_includes row.positions, "GD"
  end

  test "a mentee standing a mentee shift is not a qualified Green Dot" do
    person = create_person("Learner")
    hold_position(person, @green_dot)
    pass_green_dot_training(person)
    sign_up(person, slot_over(12.hours, 18.hours, position: @mentee))

    row = report.dirt.sole

    assert_not row.green_dot
    assert_not_includes row.positions, "GD"
  end

  # One tinted cell could only ever show the first of the two; two chips say
  # both, which is what the underlying data has always carried.
  test "a Ranger who is both a Green Dot and a Troubleshooter gets both chips" do
    person = create_person("Verde")
    hold_position(person, @green_dot)
    hold_position(person, @troubleshooter)
    pass_green_dot_training(person)
    sign_up(person, slot_over(12.hours, 18.hours, position: @green_dot))

    row = report.dirt.sole

    assert row.green_dot
    assert row.troubleshooter
  end

  test "the Green Dot head count reports women separately" do
    her = create_person("Verde")
    her.update!(gender_identity: Gender::GENDER_FEMALE)
    him = create_person("Esmeralda")
    him.update!(gender_identity: Gender::GENDER_MALE)
    slot = slot_over(12.hours, 18.hours, position: @green_dot)
    sign_up(her, slot)
    sign_up(him, slot)

    result = report

    assert_equal 2, result.green_dot_total
    assert_equal 1, result.green_dot_females
  end

  # The head count wants 90 minutes of overlap where the roster wants 45, so a
  # Green Dot leaving early appears on the roster and not in the count.
  test "a Green Dot leaving within 90 minutes is on the roster but not the count" do
    sign_up(create_person("Fading"), slot_over(6.hours, 13.hours, position: @green_dot))

    result = report

    assert_equal ["Fading"], result.dirt.map(&:callsign)
    assert_equal 0, result.green_dot_total
  end

  # --- the positions column ---

  test "a Troubleshooter is flagged unless they are also running the shift" do
    plain = create_person("Wrench")
    hold_position(plain, @troubleshooter)
    sign_up(plain, slot_over(12.hours, 18.hours))

    assert report.dirt.sole.troubleshooter

    boss = create_person("Khaki")
    hold_position(boss, @troubleshooter)
    hold_position(boss, @ood)
    sign_up(boss, slot_over(12.hours, 18.hours))

    assert_not report.dirt.find { |row| row.callsign == "Khaki" }.troubleshooter
  end

  # The column says what else this Ranger could be asked to do, so the dirt
  # shift they are already standing is not news.
  test "plain dirt positions are left out of the positions column" do
    person = create_person("Dusty")
    hold_position(person, @dirt)
    hold_position(person, @troubleshooter)
    sign_up(person, slot_over(12.hours, 18.hours))

    assert_equal ["TS"], report.dirt.sole.positions
  end

  # --- the vehicle columns ---

  # The two flags are read out of one pluck into two variables, and a shift lead
  # reading VEH where GTR was meant is being told this Ranger may take an org
  # vehicle out when all they have signed is the Vehicle Use Protocol.
  test "the motorpool agreement and the insurance flag do not cross over" do
    signer = create_person("Signer")
    PersonEvent.create!(person_id: signer.id, year: YEAR, signed_motorpool_agreement: true)
    insured = create_person("Insured")
    PersonEvent.create!(person_id: insured.id, year: YEAR, org_vehicle_insurance: true)
    slot = slot_over(12.hours, 18.hours)
    sign_up(signer, slot)
    sign_up(insured, slot)

    rows = report.dirt.index_by(&:callsign)

    assert_equal :yes, rows["Signer"].gtr
    assert_equal :no, rows["Signer"].vehicle
    assert_equal :no, rows["Insured"].gtr
    assert_equal :yes, rows["Insured"].vehicle
  end

  test "a Ranger with no person_event row for the year has signed nothing" do
    sign_up(create_person("Fresh"), slot_over(12.hours, 18.hours))

    row = report.dirt.sole

    assert_equal :no, row.gtr
    assert_equal :no, row.vehicle
  end

  # Blacklisted is the answer to both columns whatever else is on file.
  test "a vehicle blacklist overrides both columns" do
    person = create_person("Grounded")
    person.update!(vehicle_blacklisted: true)
    PersonEvent.create!(person_id: person.id, year: YEAR, signed_motorpool_agreement: true,
                        org_vehicle_insurance: true)
    sign_up(person, slot_over(12.hours, 18.hours))

    row = report.dirt.sole

    assert_equal :blacklisted, row.gtr
    assert_equal :blacklisted, row.vehicle
  end

  test "certifications flagged for this report are listed under their short title" do
    certification = Certification.create!(title: "Cardiopulmonary Resuscitation", sl_title: "CPR",
                                          on_sl_report: true)
    ignored = Certification.create!(title: "Commercial Licence", on_sl_report: false)
    person = create_person("Medic")
    PersonCertification.create!(person:, certification:)
    PersonCertification.create!(person:, certification: ignored)
    sign_up(person, slot_over(12.hours, 18.hours))

    assert_equal ["CPR"], report.dirt.sole.certifications
  end

  # --- below minimum staffing ---

  test "a position short of its minimum is listed with what it has" do
    slot = slot_over(12.hours, 18.hours, min: 3, max: 3)
    sign_up(create_person("Dusty"), slot)
    slot.update!(signed_up: 1)

    row = report.below_min.sole

    assert_equal "Dirt", row.title
    assert_equal 1, row.count
    assert_equal "3", row.need
  end

  test "a fully staffed shift reports nothing below minimum" do
    slot = slot_over(12.hours, 18.hours, min: 1)
    sign_up(create_person("Dusty"), slot)
    slot.update!(signed_up: 1)

    assert_predicate report, :fully_staffed?
  end

  test "a minimum below a maximum is reported as a range" do
    slot_over(12.hours, 18.hours, min: 2, max: 4)

    assert_equal "2 - 4", report.below_min.sole.need
  end

  # The max column defaults to zero and hundreds of older slots never had one
  # set, so zero means unset rather than "room for no one".
  test "a shift with no maximum set reports its minimum alone" do
    slot_over(12.hours, 18.hours, min: 1, max: 0)

    assert_equal "1", report.below_min.sole.need
  end

  private

  def report = ShiftLeadReport.execute(shift_start: SHIFT_START, shift_duration: SHIFT_DURATION)

  # An 18:00-06:00 window, whose leading hour reaches past midnight into the
  # next day.
  def evening_report
    ShiftLeadReport.execute(shift_start: SHIFT_START + 6.hours, shift_duration: 12.hours.to_i)
  end

  # 02:00-05:00 the morning after that window opens: inside its leading hour,
  # and a day later than the day it is listed under.
  def evening_report_slot = slot_over(26.hours, 29.hours)

  def create_position(id, title, short_title: nil, type: Position::TYPE_FRONTLINE, on_sl_report: nil)
    Position.create!(id:, title:, short_title:, type:, active: true, on_sl_report:)
  end

  # A slot placed by its offset from the day the window opens on, so every test
  # reads as "from X to Y" against the same noon-to-six window.
  def slot_over(begins_offset, ends_offset, position: @dirt, min: 1, max: 20)
    midnight = SHIFT_START.beginning_of_day
    create_slot(position, begins: midnight + begins_offset, ends: midnight + ends_offset,
                min:, max:)
  end

  def sign_up(person, slot) = PersonSlot.create!(person:, slot:)

  def hold_position(person, position) = PersonPosition.create!(person:, position:)

  def pass_green_dot_training(person)
    slot = create_slot(@gd_training, begins: Time.zone.local(YEAR, 7, 1, 9, 0, 0),
                       ends: Time.zone.local(YEAR, 7, 1, 17, 0, 0))
    TraineeStatus.create!(person_id: person.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)
  end
end
