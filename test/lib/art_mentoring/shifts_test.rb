# frozen_string_literal: true

require "test_helper"

# How ArtMentoring::Shifts turns a year of mentee timesheet entries into
# mentoring shifts (ruled 2026-10-21): the shift an entry names, else the
# nearest within the hour, else a cluster around the earliest loose sign-in;
# and which mentors are on each.
class ArtMentoring::ShiftsTest < ActiveSupport::TestCase
  include ArtMentoringTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 9, 2, 19, 0, 0)
    Current.reset
    setup_art_mentoring
    @evening = Time.zone.local(YEAR, 9, 1, 17, 45, 0)
    @mentees = %w[Tinsel Moonrake Bramble].map { |callsign| create_person(callsign) }
    @mentors = %w[Ferrous Cinder Marigold].map { |callsign| create_person(callsign) }
  end

  teardown do
    Current.reset
    travel_back
  end

  def shifts = ArtMentoring::Shifts.new(@training, YEAR)

  def mentee_callsigns(group) = group.mentee_entries.map { |sheet| sheet.person.callsign }

  test "an entry joins the shift it was signed in to, even when another starts nearer" do
    named = mentee_shift(@evening)
    nearer = mentee_shift(@evening + 40.minutes)
    mentee_entry(@mentees[0], @evening + 35.minutes, off_duty: @evening + 6.hours, slot: named)

    groups = shifts.groups

    assert_equal [named.id.to_s], groups.map(&:key)
    assert_equal named, groups.first.slot
    assert_not_includes groups.map(&:key), nearer.id.to_s
  end

  test "an entry with no shift named joins the nearer shift starting within the hour" do
    earlier = mentee_shift(@evening)
    later = mentee_shift(@evening + 1.hour)
    mentee_entry(@mentees[0], @evening + 35.minutes, off_duty: @evening + 6.hours, loose: true)

    assert_equal [later.id.to_s], shifts.groups.map(&:key)
    assert_not_includes shifts.groups.map(&:key), earlier.id.to_s
  end

  test "sign-ins matching no shift are grouped by the hour around the earliest" do
    first = mentee_entry(@mentees[0], @evening, off_duty: @evening + 6.hours, loose: true)
    mentee_entry(@mentees[1], @evening + 40.minutes, off_duty: @evening + 6.hours, loose: true)
    late = mentee_entry(@mentees[2], @evening + 70.minutes, off_duty: @evening + 6.hours, loose: true)

    groups = shifts.groups

    assert_equal ["t#{first.id}", "t#{late.id}"], groups.map(&:key)
    assert groups.all?(&:unmatched?)
    assert_equal %w[Tinsel Moonrake], mentee_callsigns(groups.first)
    assert_equal @evening, groups.first.begins
  end

  test "a mentor is on a shift when their mentor shift or their sign-in starts within the hour" do
    slot = mentee_shift(@evening)
    paired = mentor_shift(@evening)
    mentee_entry(@mentees[0], @evening, off_duty: @evening + 6.hours, slot:)
    # Signed in to the paired mentor shift 75 minutes early: the shift counts, not the sign-in.
    mentor_entry(@mentors[0], @evening - 75.minutes, off_duty: @evening + 6.hours, slot: paired)
    mentor_entry(@mentors[1], @evening + 50.minutes, off_duty: @evening + 6.hours, loose: true)
    mentor_entry(@mentors[2], @evening + 70.minutes, off_duty: @evening + 6.hours, loose: true)

    assert_equal %w[Ferrous Cinder], shifts.group(slot.id.to_s).mentors.map(&:callsign)
  end

  test "a shift is in progress while any of its mentees is still signed in" do
    slot = mentee_shift(@evening + 1.day - 1.hour)
    mentee_entry(@mentees[0], slot.begins, off_duty: slot.begins + 2.hours, slot:)
    open = mentee_entry(@mentees[1], slot.begins, slot:)
    done = mentee_shift(@evening)
    mentee_entry(@mentees[2], @evening, off_duty: @evening + 6.hours, slot: done)

    current = shifts

    assert_equal [slot.id.to_s], current.in_progress.map(&:key)
    assert_equal [done.id.to_s], current.completed.map(&:key)
    assert_equal 1, current.on_shift.size, "only the entry still open is on shift"
    assert_equal [open], current.on_shift.map(&:last)
  end

  # Each mentee entry is in one state: no mentor (needs one, on shift or not),
  # a mentor and still Pending once signed out (awaits a verdict), or done.
  test "who needs a mentor and who awaits a verdict is counted by mentee, not by shift" do
    slot = mentee_shift(@evening + 1.day - 1.hour)
    signed_out = mentee_entry(@mentees[0], slot.begins, off_duty: slot.begins + 2.hours, slot:)
    walk(signed_out, @mentors[0])
    mentee_entry(@mentees[1], slot.begins, slot:)
    done = mentee_shift(@evening)
    mentee_entry(@mentees[2], @evening, off_duty: @evening + 6.hours, slot: done)

    current = shifts
    group = current.group(slot.id.to_s)

    assert_equal %w[Moonrake], group.needing_mentor.map { |sheet| sheet.person.callsign }
    assert_equal %w[Tinsel], group.awaiting_verdict.map { |sheet| sheet.person.callsign }
    assert_equal [2, 1], [current.needing_mentor_count, current.awaiting_verdict_count],
                 "Bramble's shift has ended, and no one was paired with them"
  end

  # The shape of a year after its event: every shift over, no one paired.
  test "a mentee no one was paired with still needs a mentor after their shift" do
    slot = mentee_shift(@evening)
    paired = mentee_entry(@mentees[0], @evening, off_duty: @evening + 6.hours, slot:)
    passed = mentee_entry(@mentees[1], @evening, off_duty: @evening + 6.hours, slot:)
    mentee_entry(@mentees[2], @evening, off_duty: @evening + 6.hours, slot:)
    walk(paired, @mentors[0])
    walk(passed, @mentors[0], status: PersonMentor::STATUS_PASS)

    current = shifts
    group = current.group(slot.id.to_s)

    assert_equal %w[Bramble], group.needing_mentor.map { |sheet| sheet.person.callsign }
    assert_equal %w[Tinsel], group.awaiting_verdict.map { |sheet| sheet.person.callsign },
                 "a verdict waits on a mentor: Bramble needs one first"
    assert_equal [1, 1], [current.needing_mentor_count, current.awaiting_verdict_count]
  end

  test "a sign-in left open for more than a day has ended" do
    slot = mentee_shift(@evening - 1.day)
    forgotten = mentee_entry(@mentees[0], slot.begins, slot:)
    walk(forgotten, @mentors[0])

    current = shifts

    assert_empty current.in_progress
    assert_equal [slot.id.to_s], current.completed.map(&:key)
    assert_equal [forgotten], current.group(slot.id.to_s).awaiting_verdict
    assert_empty current.on_shift
  end

  test "a shift still to come is listed with its sign-ups, and an empty one is not" do
    future = mentee_shift(Time.zone.local(YEAR, 9, 3, 5, 45, 0))
    mentee_shift(Time.zone.local(YEAR, 9, 3, 11, 45, 0))
    sign_up(@mentees[0], future)

    upcoming = shifts.upcoming

    assert_equal [future.id], upcoming.map { |shift| shift.slot.id }
    assert_equal %w[Tinsel], upcoming.first.mentees.map(&:callsign)
    assert_empty upcoming.first.mentors, "no one signed up for the mentor shift"
  end

  test "a mentee signing in early leaves the shift's other sign-ups still to come" do
    soon = mentee_shift(Time.zone.local(YEAR, 9, 2, 19, 45, 0))
    sign_up(@mentees[0], soon)
    sign_up(@mentees[1], soon)
    mentee_entry(@mentees[0], Time.zone.local(YEAR, 9, 2, 18, 55, 0), slot: soon)

    current = shifts

    assert_equal [soon.id.to_s], current.in_progress.map(&:key)
    assert_equal [%w[Moonrake]], current.upcoming.map { |shift| shift.mentees.map(&:callsign) }
    assert_equal 1, current.upcoming_signup_count
  end

  test "another position's entries are not this training's mentee shifts" do
    other = Position.create!(title: "Khaki", type: Position::TYPE_FRONTLINE, active: true)
    entry(@mentees[0], other, @evening, off_duty: @evening + 6.hours)

    assert_empty shifts.groups
  end

  test "a training whose team flags no mentee position lists nothing" do
    @mentee_position.update!(is_art_mentee: false)
    mentee_entry(@mentees[0], @evening, off_duty: @evening + 6.hours)

    current = shifts

    assert_nil current.mentee_position
    assert_empty current.groups
  end
end
