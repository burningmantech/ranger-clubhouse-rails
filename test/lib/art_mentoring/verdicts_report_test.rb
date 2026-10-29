# frozen_string_literal: true

require "test_helper"

# Training › Mentoring › Verdicts (ArtMentoring::VerdictsReport): the year's
# verdicts newest first, each mentor's season, and a walk that outlives its
# deleted timesheet entry (ruled 2026-10-21: kept, as "Shift deleted").
class ArtMentoring::VerdictsReportTest < ActiveSupport::TestCase
  include ArtMentoringTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 9, 2, 19, 0, 0)
    Current.reset
    setup_art_mentoring
    @slot = mentee_shift(Time.zone.local(YEAR, 9, 1, 17, 45, 0))
    @ferrous = create_person("Ferrous")
    @cinder = create_person("Cinder")
    @evening = mentor_entry(@ferrous, @slot.begins - 10.minutes, off_duty: @slot.ends) # 6:10
    @tonight = mentor_entry(@ferrous, Time.zone.local(YEAR, 9, 2, 17, 35, 0)) # on shift now

    @tinsel = mentee_entry(create_person("Tinsel"), @slot.begins, off_duty: @slot.ends, slot: @slot)
    @moonrake = mentee_entry(create_person("Moonrake"), @slot.begins + 5.minutes, off_duty: @slot.ends, slot: @slot)
    @bramble = mentee_entry(create_person("Bramble"), @slot.begins + 10.minutes, off_duty: @slot.ends, slot: @slot)
    @quartz = mentee_entry(create_person("Quartz"), @slot.begins + 15.minutes, off_duty: @slot.ends, slot: @slot)

    @passed = walk(@tinsel, @ferrous, status: PersonMentor::STATUS_PASS)
    @bonked = walk(@moonrake, @cinder, status: PersonMentor::STATUS_BONK) # Cinder never signed in
    @pending = walk(@bramble, @ferrous)
    @orphan = walk(@quartz, @ferrous, status: PersonMentor::STATUS_SELF_BONK)
    @quartz.delete # the walk keeps naming it
  end

  teardown do
    Current.reset
    travel_back
  end

  def report = ArtMentoring::VerdictsReport.new(ArtMentoring::Shifts.new(@training, YEAR))

  test "verdicts are newest first, leave Pending out, and keep a deleted entry's walk last" do
    report = self.report

    assert_equal [@bonked, @passed, @orphan], report.verdicts
    assert_nil report.entry_for(@orphan)
    assert_equal @tinsel, report.entry_for(@passed)
    assert_equal [1, 2], [report.count(PersonMentor::STATUS_PASS), report.count(*ArtMentoring::VerdictsReport::BONKS)]
  end

  test "Abstained and Not completed are verdicts, counted as neither a pass nor a bonk" do
    sable = mentee_entry(create_person("Sable"), @slot.begins + 20.minutes, off_duty: @slot.ends, slot: @slot)
    rook = mentee_entry(create_person("Rook"), @slot.begins + 25.minutes, off_duty: @slot.ends, slot: @slot)
    abstained = walk(sable, @ferrous, status: PersonMentor::STATUS_ABSTAIN)
    not_completed = walk(rook, @cinder, status: PersonMentor::STATUS_NOT_COMPLETED)
    report = self.report

    assert_includes report.verdicts, abstained
    assert_includes report.verdicts, not_completed
    assert_equal [5, 1, 2], [report.count(*ArtMentoring::VerdictsReport::VERDICTS),
                             report.count(PersonMentor::STATUS_PASS), report.count(*ArtMentoring::VerdictsReport::BONKS)]
  end

  # A pass recorded on the roster with no mentor selected (owner, 2026-10-28).
  test "a pass recorded without a mentor counts as a pass and is no mentor's" do
    sable = mentee_entry(create_person("Sable"), @slot.begins + 20.minutes, off_duty: @slot.ends, slot: @slot)
    alone = PersonMentor.create!(person_id: sable.person_id, timesheet_id: sable.id, mentor_year: YEAR,
                                 position_id: @mentee_position.id, status: PersonMentor::STATUS_PASS)
    report = self.report

    assert_includes report.verdicts, alone
    assert_equal 2, report.count(PersonMentor::STATUS_PASS)
    assert_equal [@cinder, @ferrous], report.mentors.map(&:person)
  end

  test "each mentor's season counts their shifts, mentees and results, and averages only ended shifts" do
    cinder, ferrous = report.mentors

    assert_equal [@cinder, @ferrous], [cinder.person, ferrous.person], "by callsign"
    assert_equal [2, 3], [ferrous.entries.size, ferrous.mentee_count]
    assert_equal [1, 1, 1], [ferrous.count(PersonMentor::STATUS_PASS), ferrous.count(PersonMentor::STATUS_PENDING),
                             ferrous.count(*ArtMentoring::VerdictsReport::BONKS)]
    assert_equal 6.hours + 10.minutes, ferrous.average_length, "the shift still going is left out"
    assert_equal [0, 1, nil], [cinder.entries.size, cinder.mentee_count, cinder.average_length]
  end

  test "a mentor's lines put each walk on the shift they signed in to, or say they did not" do
    cinder, ferrous = report.mentors

    assert_equal [[@evening, [@passed, @pending]], [@tonight, []], [nil, [@orphan]]],
                 ferrous.lines.map { |line| [line.entry, line.walks.sort_by(&:id)] }
    assert_nil ferrous.lines.last.begins, "the deleted entry's walk has no time"

    line = cinder.lines.sole
    assert_equal [nil, @slot.begins, [@bonked], true], [line.entry, line.begins, line.walks, line.off_shift]
  end

  test "an entry moved off the mentee position keeps its walk, at its own time" do
    @tinsel.update_column(:position_id, recommended_position("Dirt - Green Dot").id)

    report = self.report

    assert_includes report.verdicts, @passed
    assert_equal @tinsel.on_duty, report.started(@passed)
    ferrous = report.mentors.find { |mentor| mentor.person == @ferrous }
    moved = ferrous.lines.find { |line| line.walks.include?(@passed) }
    assert_equal [nil, @tinsel.on_duty, false], [moved.entry, moved.begins, moved.off_shift],
                 "no mentee shift to say they missed"
  end

  # Timesheet Management can correct an entry onto another ART's mentee
  # position: its walk goes with it, as on the roster (ArtMentoring::Shifts).
  test "a walk whose entry moved to another ART's mentee position is that ART's verdict" do
    team = Team.create!(title: "Troubleshooter Team", active: true)
    troubleshooter = Position.create!(id: Position::TROUBLESHOOTER_TRAINING, title: "Troubleshooter Training",
                                      type: Position::TYPE_TRAINING, active: true, team:, has_art_mentoring: true)
    prospective = Position.create!(id: Position::TROUBLESHOOTER_MENTEE, title: "Troubleshooter Prospective",
                                   type: Position::TYPE_FRONTLINE, active: true, team:, is_art_mentee: true)
    @tinsel.update_column(:position_id, prospective.id)

    assert_not_includes report.verdicts, @passed
    assert_equal [@passed], ArtMentoring::VerdictsReport.new(ArtMentoring::Shifts.new(troubleshooter, YEAR)).verdicts
  end
end
