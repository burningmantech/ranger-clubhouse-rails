# frozen_string_literal: true

require "test_helper"

# One verdict per person-year out of retrieve_all_mentors_for_ids, which the
# review pane's history, the pipeline pages' bonk chip, Post Season Summary,
# the Alpha Schedule, the Acceptance Sheets and the mentor worksheet all read.
# A year's rows can disagree -- rows this app did not write -- and the verdict
# is settled by VERDICT_PRECEDENCE rather than by whichever row comes back first.
class PersonMentorTest < ActiveSupport::TestCase
  YEAR = 2026

  setup do
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

  test "a mentor's mentee list survives rows naming deleted people" do
    mentor = @mentors.first
    gone_mentor_id, gone_mentee_id = 999_999_001, 999_999_002
    PersonMentor.create!(person: @mentee, mentor:, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    PersonMentor.insert_all!([
      { person_id: @mentee.id, mentor_id: gone_mentor_id, mentor_year: YEAR, status: PersonMentor::STATUS_PASS },
      { person_id: gone_mentee_id, mentor_id: mentor.id, mentor_year: YEAR, status: PersonMentor::STATUS_PASS }
    ])

    cohort = PersonMentor.retrieve_mentees_for_person(mentor.id, position_id: Position::ALPHA).find { |c| c.year == YEAR }

    assert_equal [@mentee.id], cohort.alphas.map(&:id)
    assert_includes cohort.alphas.first.mentors.map(&:callsign), "Deleted ##{gone_mentor_id}"
  end

  # An ART walk is one row per mentor per mentee shift, named by the mentee's
  # timesheet entry. person_mentor carries no foreign keys, so any id stands in
  # for one.
  test "one mentee shift takes each mentor once" do
    shift = 9_001
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
    [9_001, 9_002].each do |shift|
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
