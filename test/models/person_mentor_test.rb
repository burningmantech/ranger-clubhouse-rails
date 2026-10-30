# frozen_string_literal: true

require "test_helper"

# One verdict per person-year out of retrieve_all_mentors_for_ids, which the
# review pane's history, the pipeline pages' bonk chip, Post Season Summary,
# the Alpha Schedule, the Acceptance Sheets and the mentor worksheet all read.
# A year's rows can disagree -- rows this app did not write -- and the verdict
# is settled by VERDICT_PRECEDENCE rather than by whichever row comes back first.
class PersonMentorTest < ActiveSupport::TestCase
  include AlphaPositionTestHelper
  include ArtMentoringTestHelper

  YEAR = 2026

  setup do
    setup_alpha_position
    setup_cheetah_cub_position
    setup_art_mentoring
    @mentee = person(:alpha_ranger)
    # The losing status goes in first, against the lower mentor id, so it is
    # the row `first` read whichever order the database returned them in.
    @mentors = [person(:active_ranger), person(:echelon_ranger)].sort_by(&:id)
  end

  test "a pass and a bonk for one walk resolve to the bonk" do
    record(PersonMentor::STATUS_PASS, PersonMentor::STATUS_BONK)

    assert_equal PersonMentor::STATUS_BONK, year_status
  end

  test "a bonk outranks a self-bonk, and any verdict outranks pending" do
    record(PersonMentor::STATUS_SELF_BONK, PersonMentor::STATUS_BONK)

    assert_equal PersonMentor::STATUS_BONK, year_status

    PersonMentor.where(person: @mentee).delete_all
    record(PersonMentor::STATUS_PENDING, PersonMentor::STATUS_PASS)

    assert_equal PersonMentor::STATUS_PASS, year_status
  end

  test "a row written without a position is an Alpha walk" do
    row = PersonMentor.create!(person: @mentee, mentor: @mentors.first, mentor_year: YEAR,
                               status: PersonMentor::STATUS_PASS)

    assert_equal Position::ALPHA, row.position_id
  end

  test "another position's walk is invisible to the Alpha history" do
    PersonMentor.create!(person: @mentee, mentor: @mentors.first, mentor_year: YEAR,
                         position_id: Position::CHEETAH_CUB, status: PersonMentor::STATUS_BONK)

    assert_nil year_status
  end

  test "the mentoring page's year status is the year's verdict, not the first mentor's by callsign" do
    first, second = [person(:active_ranger), person(:echelon_ranger)].sort_by(&:callsign)
    PersonMentor.create!(person: @mentee, mentor: first, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    PersonMentor.create!(person: @mentee, mentor: second, mentor_year: YEAR, status: PersonMentor::STATUS_BONK)

    passing = PersonMentor.retrieve_passing_for_person(@mentee.id, position_id: Position::ALPHA)

    assert_equal PersonMentor::STATUS_BONK, passing.current_status
  end

  # A deleted account takes its own walks with it (Person's person_mentors);
  # the walks it mentored stay, naming it by id. mentor_id has no key.
  test "a mentor's mentee list survives a row naming a deleted mentor" do
    mentor = @mentors.first
    gone_mentor_id = 999_999_001
    PersonMentor.create!(person: @mentee, mentor:, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    PersonMentor.insert_all!([
      { person_id: @mentee.id, mentor_id: gone_mentor_id, mentor_year: YEAR, status: PersonMentor::STATUS_PASS }
    ])

    cohort = PersonMentor.retrieve_mentees_for_person(mentor.id, position_id: Position::ALPHA).find { |c| c.year == YEAR }

    assert_equal [@mentee.id], cohort.alphas.map(&:id)
    assert_includes cohort.alphas.first.mentors.map(&:callsign), "Deleted ##{gone_mentor_id}"
  end

  # An ART walk is one row per mentor per mentee shift, named by the mentee's
  # timesheet entry.
  test "one mentee shift takes each mentor once" do
    shift = mentee_entry(@mentee, Time.zone.local(YEAR, 9, 1, 18, 0, 0)).id
    PersonMentor.create!(person: @mentee, mentor: @mentors.first, mentor_year: YEAR, timesheet_id: shift,
                         position_id: Position::GREEN_DOT_MENTEE, status: PersonMentor::STATUS_PENDING)
    second = PersonMentor.new(person: @mentee, mentor: @mentors.last, mentor_year: YEAR, timesheet_id: shift,
                              position_id: Position::GREEN_DOT_MENTEE, status: PersonMentor::STATUS_PENDING)
    assert second.valid?, "a second mentor on the same shift"

    again = PersonMentor.new(person: @mentee, mentor: @mentors.first, mentor_year: YEAR, timesheet_id: shift,
                             position_id: Position::GREEN_DOT_MENTEE, status: PersonMentor::STATUS_PENDING)
    assert_not again.valid?
    assert_equal ["That mentor is already recorded for this mentee shift"], again.errors[:timesheet_id]
    assert_raises(ActiveRecord::RecordNotUnique) { again.save!(validate: false) }
  end

  test "one mentor may walk one mentee on two shifts in a year" do
    [1, 2].each do |day|
      shift = mentee_entry(@mentee, Time.zone.local(YEAR, 9, day, 18, 0, 0)).id
      PersonMentor.create!(person: @mentee, mentor: @mentors.first, mentor_year: YEAR, timesheet_id: shift,
                           position_id: Position::GREEN_DOT_MENTEE, status: PersonMentor::STATUS_PASS)
    end

    assert_equal 2, PersonMentor.where(person: @mentee, mentor: @mentors.first, mentor_year: YEAR).count
  end

  # The database's person_id key ends in timesheet_id, which an Alpha row
  # leaves NULL, so only the model refuses a mentor recorded twice for one Alpha.
  test "an Alpha walk records each mentor once a year" do
    PersonMentor.create!(person: @mentee, mentor: @mentors.first, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    again = PersonMentor.new(person: @mentee, mentor: @mentors.first, mentor_year: YEAR,
                             status: PersonMentor::STATUS_PASS)

    assert_not again.valid?
    assert_equal ["That mentor is already recorded for this person and year"], again.errors[:mentor_id]

    again.mentor_year = YEAR - 1
    assert again.valid?, again.errors.full_messages.to_sentence
  end

  # Abstained and Not completed are ART verdicts (ruled 2026-10-27): an Alpha
  # walk, read by every Alpha page and report, records only the four.
  test "an ART walk may end Abstained or Not completed, and an Alpha walk may not" do
    alpha = PersonMentor.new(person: @mentee, mentor: @mentors.first, mentor_year: YEAR,
                             status: PersonMentor::STATUS_ABSTAIN)
    assert_not alpha.valid?
    assert_equal ["Status is not included in the list."], alpha.errors[:status]

    shift = mentee_entry(@mentee, Time.zone.local(YEAR, 9, 1, 18, 0, 0)).id
    art = PersonMentor.create!(person: @mentee, mentor: @mentors.first, mentor_year: YEAR, timesheet_id: shift,
                               position_id: Position::GREEN_DOT_MENTEE, status: PersonMentor::STATUS_NOT_COMPLETED)
    assert_equal PersonMentor::STATUS_NOT_COMPLETED, art.reload.status, "the column holds it"
  end

  # A pass recorded on the ART roster with no mentor selected (owner,
  # 2026-10-28) is one row naming none; every other walk names its mentor.
  test "only an ART walk's pass may name no mentor, once per mentee shift" do
    shift = mentee_entry(@mentee, Time.zone.local(YEAR, 9, 1, 18, 0, 0)).id
    art = { person: @mentee, mentor_year: YEAR, timesheet_id: shift, position_id: Position::GREEN_DOT_MENTEE }
    pass = PersonMentor.create!(**art, status: PersonMentor::STATUS_PASS)
    assert_nil pass.reload.mentor_id, "the column takes NULL"

    again = PersonMentor.new(**art, status: PersonMentor::STATUS_PASS)
    assert_not again.valid?
    assert again.errors.of_kind?(:timesheet_id, :taken), "one mentor-less row per mentee shift"
    # The database holds it too, for a save racing past the check: mentor_key
    # reads 0 for the NULL, which a unique key never matches against another.
    assert_raises(ActiveRecord::RecordNotUnique) { again.save!(validate: false) }

    later = mentee_entry(@mentee, Time.zone.local(YEAR, 9, 2, 18, 0, 0)).id
    bonk = PersonMentor.new(**art, timesheet_id: later, status: PersonMentor::STATUS_BONK)
    assert_not bonk.valid?
    assert bonk.errors.of_kind?(:mentor, :blank)
    alpha = PersonMentor.new(person: @mentee, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    assert_not alpha.valid?
    assert alpha.errors.of_kind?(:mentor, :blank)
  end

  # A deleted account leaves the walks it mentored, naming it by id. As the
  # required belongs_to it replaced, the mentor check runs only when mentor_id
  # changes.
  test "a walk whose mentor's account is gone still takes a new result and notes" do
    shift = mentee_entry(@mentee, Time.zone.local(YEAR, 9, 3, 18, 0, 0)).id
    walk = PersonMentor.create!(person: @mentee, mentor: @mentors.first, mentor_year: YEAR, timesheet_id: shift,
                                position_id: Position::GREEN_DOT_MENTEE, status: PersonMentor::STATUS_PENDING)
    gone = Person.maximum(:id) + 1
    walk.update_column(:mentor_id, gone)

    assert walk.reload.update(status: PersonMentor::STATUS_BONK, notes: "Left early."), walk.errors.full_messages.to_sentence

    walk.mentor_id = gone + 1
    assert_not walk.valid?
    assert walk.errors.of_kind?(:mentor, :blank), "a new mentor must exist"
  end

  test "either ART verdict outranks a pass and yields to a bonk" do
    assert_equal PersonMentor::STATUS_ABSTAIN,
                 PersonMentor.year_verdict([PersonMentor::STATUS_PASS, PersonMentor::STATUS_ABSTAIN])
    assert_equal PersonMentor::STATUS_NOT_COMPLETED,
                 PersonMentor.year_verdict([PersonMentor::STATUS_ABSTAIN, PersonMentor::STATUS_NOT_COMPLETED])
    assert_equal PersonMentor::STATUS_SELF_BONK,
                 PersonMentor.year_verdict([PersonMentor::STATUS_NOT_COMPLETED, PersonMentor::STATUS_SELF_BONK])
  end

  private

  def record(*statuses)
    statuses.zip(@mentors).each do |status, mentor|
      PersonMentor.create!(person: @mentee, mentor:, mentor_year: YEAR, status:)
    end
  end

  def year_status
    PersonMentor.retrieve_all_mentors_for_ids([@mentee.id], position_id: Position::ALPHA).dig(@mentee.id, YEAR, :status)
  end
end
