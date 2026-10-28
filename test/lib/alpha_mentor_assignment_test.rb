# frozen_string_literal: true

require "test_helper"

# The Alpha Mentor Assignments data layer: the roster, the mentor pool, the
# save's validation and sync semantics, and the pod fill.
#
# Fresh people rather than fixture ones wherever mentor history is asserted on:
# person_mentor.yml pre-seeds pass/bonk rows for several fixture people, and
# person.yml carries an Alpha of its own ("AlphaNewbie") who is on every roster.
class AlphaMentorAssignmentTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 25, 12, 0, 0)
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)
    @mentor_position = Position.create!(id: Position::MENTOR, title: "Mentor",
                                        type: Position::TYPE_MENTORING, active: true)

    @slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                                         description: "Saturday Day")

    @alpha = create_person("Zebra", status: Person::ALPHA)
    @mentor = create_person("Firecracker")
    @other_mentor = create_person("HotShot")
    [@mentor, @other_mentor].each do |person|
      PersonPosition.create!(person_id: person.id, position_id: Position::MENTOR)
    end
  end

  teardown do
    Current.reset
    travel_back
  end

  def entry_for(person, year: YEAR)
    AlphaMentorAssignment.roster(year).find { |entry| entry.person.id == person.id }
  end

  def row(person, status:, mentor_ids: [])
    AlphaMentorAssignment::Row.new(person_id: person.id, status:, mentor_ids:)
  end

  # ---------------------------------------------------------------- roster

  test "the roster is everyone holding Alpha status right now, callsign sorted" do
    create_person("apple", status: Person::ALPHA)
    create_person("Banana", status: Person::ALPHA)
    create_person("NotAnAlpha", status: Person::ACTIVE)

    callsigns = AlphaMentorAssignment.roster(YEAR).map { |entry| entry.person.callsign }

    # Relative order, because the fixtures carry an Alpha of their own.
    assert_equal ["apple", "Banana", "Zebra"], callsigns & ["apple", "Banana", "Zebra"]
    assert_not_includes callsigns, "NotAnAlpha"
  end

  test "an Alpha with no mentor rows reads as pending with no mentors" do
    entry = entry_for(@alpha)

    assert_equal PersonMentor::STATUS_PENDING, entry.status
    assert_empty entry.mentors
    assert entry.pending?
  end

  test "stored mentors and the year's status land on the entry, callsign sorted" do
    PersonMentor.create!(person: @alpha, mentor: @other_mentor, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)
    PersonMentor.create!(person: @alpha, mentor: @mentor, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)

    entry = entry_for(@alpha)

    assert_equal ["Firecracker", "HotShot"], entry.mentors.map { |mentor| mentor[:callsign] }
    assert_equal PersonMentor::STATUS_PASS, entry.status
    assert entry.passed?
  end

  test "prior years appear newest first and exclude the year being recorded" do
    PersonMentor.create!(person: @alpha, mentor: @mentor, mentor_year: YEAR - 2,
                         status: PersonMentor::STATUS_BONK)
    PersonMentor.create!(person: @alpha, mentor: @mentor, mentor_year: YEAR - 1,
                         status: PersonMentor::STATUS_SELF_BONK)
    PersonMentor.create!(person: @alpha, mentor: @mentor, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PENDING)

    years = entry_for(@alpha).prior_years

    assert_equal [YEAR - 1, YEAR - 2], years.map { |year| year[:year] }
  end

  test "this year's Alpha shift sign-ups land on the entry, earliest first" do
    later = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 27, 8, 0, 0),
                                         description: "Sunday Day")
    stale = create_slot(@alpha_position, begins: Time.zone.local(YEAR - 1, 8, 27, 8, 0, 0),
                                         description: "Last year")
    [later, @slot, stale].each { |slot| PersonSlot.create!(person_id: @alpha.id, slot_id: slot.id) }

    assert_equal [@slot.id, later.id], entry_for(@alpha).alpha_slots.map(&:id)
  end

  test "an open Alpha timesheet on one of this year's shifts marks the entry checked in" do
    Timesheet.create!(person_id: @alpha.id, position_id: @alpha_position.id, slot_id: @slot.id,
                      on_duty: Current.time - 1.hour, additional_notes: "signed in")

    entry = entry_for(@alpha)

    assert entry.checked_in?
    assert_equal @slot.id, entry.shift_slot.id
    assert_not entry.walking_unknown?
  end

  test "an open Alpha timesheet with no shift attached is walking unknown" do
    sheet = Timesheet.create!(person_id: @alpha.id, position_id: @alpha_position.id,
                              on_duty: Current.time - 1.hour, additional_notes: "signed in")
    # associate_slot attaches any Alpha slot beginning within an hour; null it
    # out to reproduce the very-early check-in this warning exists for.
    sheet.update_column(:slot_id, nil)

    entry = entry_for(@alpha)

    assert entry.checked_in?
    assert_nil entry.shift_slot
    assert entry.walking_unknown?
  end

  test "an open Alpha timesheet from a past year does not mark the entry checked in" do
    Timesheet.create!(person_id: @alpha.id, position_id: @alpha_position.id,
                      on_duty: Time.zone.local(YEAR - 1, 8, 26, 8, 0, 0),
                      additional_notes: "never closed")

    assert_not entry_for(@alpha).checked_in?, "a stale open timesheet is not a check-in for this year"
  end

  test "a fourth mentor for one year is reported as overflow rather than hidden" do
    third = create_person("Tulsa")
    fourth = create_person("Whiskey")
    [third, fourth].each { |p| PersonPosition.create!(person_id: p.id, position_id: Position::MENTOR) }
    [@mentor, @other_mentor, third, fourth].each do |mentor|
      PersonMentor.create!(person: @alpha, mentor:, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    end

    entry = entry_for(@alpha)

    assert entry.overflow?
    assert_equal ["Whiskey"], entry.overflow_mentors.map { |mentor| mentor[:callsign] }
  end

  # ----------------------------------------------------------- mentor pool

  test "the mentor pool is people holding the Mentor position, callsign sorted" do
    pool = AlphaMentorAssignment.mentor_pool(YEAR)

    assert_equal ["Firecracker", "HotShot"], pool.map(&:callsign)
    assert_not pool.first.on_duty?
  end

  test "a mentor signed in on the Mentor position this year reads as on duty" do
    Timesheet.create!(person_id: @mentor.id, position_id: @mentor_position.id,
                      on_duty: Current.time - 1.hour, additional_notes: "signed in")

    pool = AlphaMentorAssignment.mentor_pool(YEAR)

    assert pool.find { |mentor| mentor.id == @mentor.id }.on_duty?
    assert_not pool.find { |mentor| mentor.id == @other_mentor.id }.on_duty?
  end

  test "a stored mentor who has lost the position is offered as a former mentor" do
    lapsed = create_person("Moondance")
    PersonMentor.create!(person: @alpha, mentor: lapsed, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)

    entries = AlphaMentorAssignment.roster(YEAR)
    pool = AlphaMentorAssignment.mentor_pool(YEAR)

    assert_equal ["Moondance"], AlphaMentorAssignment.former_mentors(entries, pool).map(&:callsign)
  end

  # ------------------------------------------------------------- save rules

  test "a new assignment writes one row per mentor at the given status" do
    result = AlphaMentorAssignment.assign!(
      YEAR, [row(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor.id, @other_mentor.id])]
    )

    assert result.ok?
    assert_equal 1, result.saved_count
    rows = PersonMentor.where(person_id: @alpha.id, mentor_year: YEAR)
    assert_equal 2, rows.count
    assert_equal [PersonMentor::STATUS_PASS], rows.pluck(:status).uniq
  end

  test "an unchanged mentor set only restates the status and keeps the row ids" do
    record = PersonMentor.create!(person: @alpha, mentor: @mentor, mentor_year: YEAR,
                                  status: PersonMentor::STATUS_PENDING)

    AlphaMentorAssignment.assign!(
      YEAR, [row(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor.id])]
    )

    assert_equal PersonMentor::STATUS_PASS, record.reload.status
  end

  test "changing the mentor set only touches the mentors that actually changed" do
    kept = PersonMentor.create!(person: @alpha, mentor: @mentor, mentor_year: YEAR,
                                status: PersonMentor::STATUS_PENDING)
    dropped = PersonMentor.create!(person: @alpha, mentor: @other_mentor, mentor_year: YEAR,
                                   status: PersonMentor::STATUS_PENDING)
    added = create_person("Tulsa")
    PersonPosition.create!(person_id: added.id, position_id: Position::MENTOR)

    AlphaMentorAssignment.assign!(
      YEAR, [row(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor.id, added.id])]
    )

    assert_equal PersonMentor::STATUS_PASS, kept.reload.status, "the kept mentor keeps its row"
    assert_not PersonMentor.exists?(dropped.id)
    assert PersonMentor.exists?(person_id: @alpha.id, mentor_id: added.id, mentor_year: YEAR)
  end

  test "blanking every mentor on a pending row clears the year's assignments" do
    PersonMentor.create!(person: @alpha, mentor: @mentor, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PENDING)

    result = AlphaMentorAssignment.assign!(YEAR, [row(@alpha, status: PersonMentor::STATUS_PENDING)])

    assert result.ok?
    assert_equal 1, result.cleared_count
    assert_empty PersonMentor.where(person_id: @alpha.id, mentor_year: YEAR)
  end

  test "clearing the Alpha row leaves another position's walk for the same year alone" do
    PersonMentor.create!(person: @alpha, mentor: @mentor, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PENDING)
    other = PersonMentor.create!(person: @alpha, mentor: @mentor, mentor_year: YEAR,
                                 position_id: Position::CHEETAH_CUB, status: PersonMentor::STATUS_PASS)

    result = AlphaMentorAssignment.assign!(YEAR, [row(@alpha, status: PersonMentor::STATUS_PENDING)])

    assert result.ok?
    assert_equal 1, result.cleared_count
    assert_equal [other.id], PersonMentor.where(person_id: @alpha.id, mentor_year: YEAR).ids
  end

  test "an untouched row with nothing stored records nothing" do
    result = AlphaMentorAssignment.assign!(YEAR, [row(@alpha, status: PersonMentor::STATUS_PENDING)])

    assert result.ok?
    assert_equal 0, result.changed_count
  end

  test "the same mentor picked twice is refused and nothing is written" do
    result = nil

    assert_no_difference "PersonMentor.count" do
      result = AlphaMentorAssignment.assign!(
        YEAR, [row(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor.id, @mentor.id])]
      )
    end

    assert_not result.ok?
    assert_match(/same mentor is listed twice/, result.row_errors[@alpha.id])
  end

  test "a result without a mentor is refused rather than silently dropped" do
    result = AlphaMentorAssignment.assign!(YEAR, [row(@alpha, status: PersonMentor::STATUS_BONK)])

    assert_not result.ok?
    assert_match(/at least one mentor/, result.row_errors[@alpha.id])
  end

  test "an ART-only verdict is refused on the Alpha sheet" do
    result = AlphaMentorAssignment.assign!(
      YEAR, [row(@alpha, status: PersonMentor::STATUS_ABSTAIN, mentor_ids: [@mentor.id])]
    )

    assert_not result.ok?
    assert_equal "Pick a status from the list.", result.row_errors[@alpha.id]
  end

  test "a mentor who does not hold the position is refused by callsign" do
    outsider = create_person("Sunburn")

    result = AlphaMentorAssignment.assign!(
      YEAR, [row(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [outsider.id])]
    )

    assert_not result.ok?
    assert_match(/Sunburn does not hold the Mentor position/, result.row_errors[@alpha.id])
  end

  test "a mentor already stored for the Alpha is allowed through after losing the position" do
    lapsed = create_person("Moondance")
    PersonMentor.create!(person: @alpha, mentor: lapsed, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PENDING)

    result = AlphaMentorAssignment.assign!(
      YEAR, [row(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [lapsed.id])]
    )

    assert result.ok?, "re-saving a stored assignment must not fail because the mentor lapsed"
  end

  test "one bad row stops the whole sheet from being written" do
    other = create_person("DustBunny", status: Person::ALPHA)

    assert_no_difference "PersonMentor.count" do
      AlphaMentorAssignment.assign!(YEAR, [
                                      row(other, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor.id]),
                                      row(@alpha, status: PersonMentor::STATUS_PASS,
                                          mentor_ids: [@mentor.id, @mentor.id])
                                    ])
    end
  end

  test "a row for someone who is not a current Alpha is dropped" do
    ranger = create_person("Ranger", status: Person::ACTIVE)

    assert_no_difference "PersonMentor.count" do
      result = AlphaMentorAssignment.assign!(
        YEAR, [row(ranger, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor.id])]
      )
      assert result.ok?
    end
  end

  test "recording an assignment writes an audit row" do
    assert_difference -> { ActionLog.where(event: "person-mentor-create").count }, 1 do
      AlphaMentorAssignment.assign!(
        YEAR, [row(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor.id])]
      )
    end
  end

  # ------------------------------------------------------- bonk confirmation

  test "a sheet of passes with no bonks asks for confirmation" do
    rows = [row(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor.id])]

    assert AlphaMentorAssignment.needs_bonk_confirmation?(rows)
  end

  test "a sheet with a bonk does not ask" do
    other = create_person("DustBunny", status: Person::ALPHA)
    rows = [
      row(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor.id]),
      row(other, status: PersonMentor::STATUS_BONK, mentor_ids: [@mentor.id])
    ]

    assert_not AlphaMentorAssignment.needs_bonk_confirmation?(rows)
  end

  test "a self-bonk does not count as a bonk, matching upstream" do
    other = create_person("DustBunny", status: Person::ALPHA)
    rows = [
      row(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor.id]),
      row(other, status: PersonMentor::STATUS_SELF_BONK, mentor_ids: [@mentor.id])
    ]

    assert AlphaMentorAssignment.needs_bonk_confirmation?(rows)
  end

  test "a sheet with no passes does not ask" do
    rows = [row(@alpha, status: PersonMentor::STATUS_PENDING, mentor_ids: [@mentor.id])]

    assert_not AlphaMentorAssignment.needs_bonk_confirmation?(rows)
  end

  # ------------------------------------------------------------- pod prefill

  test "pod prefill fills blank mentor slots from the trio and reports who it touched" do
    set = Pod.create_alpha_set!(@slot)
    set.add_person!(@mentor)
    set.add_person!(@other_mentor)
    set.sub_pods.find(&:alpha?).add_person!(@alpha)

    rows = { @alpha.id => row(@alpha, status: PersonMentor::STATUS_PENDING) }
    prefill = AlphaMentorAssignment.pod_prefill(@slot, rows)

    assert_equal [@mentor.id, @other_mentor.id].sort, prefill.rows[@alpha.id].mentor_ids.sort
    assert_equal ["Zebra"], prefill.filled
    assert_empty prefill.skipped
  end

  test "pod prefill leaves an Alpha who already has a mentor alone" do
    set = Pod.create_alpha_set!(@slot)
    set.add_person!(@mentor)
    set.sub_pods.find(&:alpha?).add_person!(@alpha)

    rows = { @alpha.id => row(@alpha, status: PersonMentor::STATUS_PENDING, mentor_ids: [@other_mentor.id]) }
    prefill = AlphaMentorAssignment.pod_prefill(@slot, rows)

    assert_equal [@other_mentor.id], prefill.rows[@alpha.id].mentor_ids
    assert_equal ["Zebra"], prefill.skipped
    assert_empty prefill.filled
  end

  # A pod is formed from the whole mentor cadre (Khaki, Cheetah, Lead), but only
  # a Mentor-position holder can be recorded here. Copying the rest in would put
  # an id in the row that the select cannot render, so it vanishes silently.
  test "pod prefill skips pod mentors who do not hold the Mentor position" do
    khaki = create_person("Sundown")
    set = Pod.create_alpha_set!(@slot)
    set.add_person!(khaki)
    set.add_person!(@mentor)
    set.sub_pods.find(&:alpha?).add_person!(@alpha)

    rows = { @alpha.id => row(@alpha, status: PersonMentor::STATUS_PENDING) }
    prefill = AlphaMentorAssignment.pod_prefill(@slot, rows)

    assert_equal [@mentor.id], prefill.rows[@alpha.id].mentor_ids
    assert_equal ["Sundown"], prefill.not_assignable
    assert_equal ["Zebra"], prefill.filled
  end

  test "an Alpha whose pod holds no assignable mentor is not reported as filled" do
    khaki = create_person("Sundown")
    set = Pod.create_alpha_set!(@slot)
    set.add_person!(khaki)
    set.sub_pods.find(&:alpha?).add_person!(@alpha)

    rows = { @alpha.id => row(@alpha, status: PersonMentor::STATUS_PENDING) }
    prefill = AlphaMentorAssignment.pod_prefill(@slot, rows)

    assert_empty prefill.rows[@alpha.id].mentor_ids
    assert_empty prefill.filled
    assert_equal ["Sundown"], prefill.not_assignable
  end

  test "pod prefill reports pod members who are not rows on the sheet" do
    set = Pod.create_alpha_set!(@slot)
    set.add_person!(@mentor)
    missing = create_person("Ember", status: Person::ALPHA)
    set.sub_pods.find(&:alpha?).add_person!(missing)

    prefill = AlphaMentorAssignment.pod_prefill(@slot, {})

    assert_equal ["Ember"], prefill.not_listed
  end

  test "pod prefill reports how many pods the shift had" do
    bare = AlphaMentorAssignment.pod_prefill(@slot, {})
    assert_not bare.pods?, "a shift with no pods must be distinguishable from an empty fill"

    Pod.create_alpha_set!(@slot)
    formed = AlphaMentorAssignment.pod_prefill(@slot, {})

    assert formed.pods?
    assert_equal 1, formed.pod_count
  end

  test "pod prefill writes nothing" do
    set = Pod.create_alpha_set!(@slot)
    set.add_person!(@mentor)
    set.sub_pods.find(&:alpha?).add_person!(@alpha)

    assert_no_difference "PersonMentor.count" do
      AlphaMentorAssignment.pod_prefill(@slot, { @alpha.id => row(@alpha, status: PersonMentor::STATUS_PENDING) })
    end
  end

  test "pod prefill takes only the first three mentors of a large pod" do
    set = Pod.create_alpha_set!(@slot)
    %w[Alfa Bravo Charlie Delta].each do |callsign|
      mentor = create_person(callsign)
      PersonPosition.create!(person_id: mentor.id, position_id: Position::MENTOR)
      set.add_person!(mentor)
    end
    set.sub_pods.find(&:alpha?).add_person!(@alpha)

    prefill = AlphaMentorAssignment.pod_prefill(
      @slot, { @alpha.id => row(@alpha, status: PersonMentor::STATUS_PENDING) }
    )

    assert_equal AlphaMentorAssignment::MENTOR_SLOTS, prefill.rows[@alpha.id].mentor_ids.size
  end
end
