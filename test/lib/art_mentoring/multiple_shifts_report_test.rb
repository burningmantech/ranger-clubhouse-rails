# frozen_string_literal: true

require "test_helper"

# Training › Mentoring › Multiple Shifts (ArtMentoring::MultipleShiftsReport):
# who has more than one mentee shift this year, rangered or signed up for.
class ArtMentoring::MultipleShiftsReportTest < ActiveSupport::TestCase
  include ArtMentoringTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  RANGERED = ArtMentoring::MultipleShiftsReport::RANGERED
  SIGNED_UP = ArtMentoring::MultipleShiftsReport::SIGNED_UP

  setup do
    travel_to Time.zone.local(YEAR, 9, 2, 19, 0, 0)
    Current.reset
    setup_art_mentoring
    @last_night = mentee_shift(Time.zone.local(YEAR, 9, 1, 17, 45, 0))
    @tonight = mentee_shift(Time.zone.local(YEAR, 9, 2, 17, 45, 0))
    @soon = mentee_shift(Time.zone.local(YEAR, 9, 2, 19, 30, 0))
    @tomorrow = mentee_shift(Time.zone.local(YEAR, 9, 3, 5, 45, 0))
  end

  teardown do
    Current.reset
    travel_back
  end

  def rows = ArtMentoring::MultipleShiftsReport.new(ArtMentoring::Shifts.new(@training, YEAR)).rows

  def ended(person, slot) = mentee_entry(person, slot.begins, off_duty: slot.ends, slot:)

  def callsigns(rows) = rows.map { |row| row.person.callsign }

  test "a mentee with two shifts of either kind is listed, and one with a single shift is not" do
    tinsel = create_person("Tinsel")
    ended(tinsel, @last_night)
    mentee_entry(tinsel, @tonight.begins, slot: @tonight)
    moonrake = create_person("Moonrake")
    ended(moonrake, @last_night)
    sign_up(moonrake, @tomorrow)
    paprika = create_person("Paprika")
    sign_up(paprika, @soon)
    sign_up(paprika, @tomorrow)
    ended(create_person("Bramble"), @last_night)

    rows = self.rows

    assert_equal %w[Moonrake Paprika Tinsel], callsigns(rows)
    moonrake_row, paprika_row, tinsel_row = rows
    assert_equal [2, 0, true], [tinsel_row.rangered, tinsel_row.signups.size, tinsel_row.on_shift?]
    assert_equal [1, [@tomorrow], true], [moonrake_row.rangered, moonrake_row.signups, moonrake_row.signed_up_again?]
    assert_equal [0, [@soon, @tomorrow], false],
                 [paprika_row.rangered, paprika_row.signups, paprika_row.signed_up_again?]
    assert_equal [%w[Tinsel], %w[Moonrake]],
                 [callsigns(rows.select { |row| row.kind?(RANGERED) }),
                  callsigns(rows.select { |row| row.kind?(SIGNED_UP) })]
  end

  test "someone who signed in early to a shift is rangering it, not also signed up for it" do
    quartz = create_person("Quartz")
    ended(quartz, @last_night)
    sign_up(quartz, @soon)
    mentee_entry(quartz, @soon.begins - 35.minutes, slot: @soon)

    row = rows.sole

    assert_equal [2, []], [row.rangered, row.signups]
  end

  test "the latest verdict is the walk on the latest ended shift, and the mentors are every walk's" do
    tinsel = create_person("Tinsel")
    first = ended(tinsel, @last_night)
    passed = walk(first, create_person("Ferrous"), status: PersonMentor::STATUS_PASS)
    walk(mentee_entry(tinsel, @tonight.begins, slot: @tonight), create_person("Cinder"))

    row = rows.sole

    assert_equal [passed], row.latest_walk.rows, "the shift still going has no verdict yet"
    assert_equal %w[Ferrous Cinder], row.mentors.map(&:callsign)
  end
end
