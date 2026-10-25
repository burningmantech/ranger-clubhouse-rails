# frozen_string_literal: true

require "test_helper"

# The surveys a person still owes: a training survey is asked of the sessions
# the person passed, and a mentoring survey of the shifts that had mentees.
class SurveyUnansweredFinderTest < ActiveSupport::TestCase
  include SurveyTestHelper
  include TrainingSlotTestHelper

  YEAR = 2026

  setup do
    setup_survey_positions
  end

  test "a training survey is asked only of a session the person passed" do
    create_survey(position: @dirt, year: YEAR)
    session = create_slot(@dirt, begins: Time.zone.local(YEAR, 5, 2, 9, 0, 0))
    ranger = person(:active_ranger)
    PersonSlot.create!(person_id: ranger.id, slot_id: session.id)
    row = TraineeStatus.create!(person: ranger, slot: session, status: TraineeStatus::STATUS_NOT_PASSED)

    owed = -> { SurveyUnansweredFinder.new(ranger.id, YEAR, Person::ACTIVE).call.sessions.map(&:id) }

    assert_empty owed.call
    row.update!(status: TraineeStatus::STATUS_PASSED)
    assert_equal [session.id], owed.call
  end

  # A mentee counts when they went on duty within an hour of the shift's start.
  test "a mentoring survey is asked of a shift that had mentees, under the survey's own type" do
    create_survey(position: @gd_mentor, type: Survey::MENTOR_FOR_MENTEES, year: YEAR, mentoring_position: @gd_mentee)
    shift = create_slot(@gd_mentor, begins: Time.zone.local(YEAR, 8, 30, 10, 0, 0), description: "Burn Night")
    mentor = person(:active_ranger)
    mentee = person(:ranger_with_custom_gender)
    Timesheet.create!(person: mentor, position: @gd_mentor, slot: shift, on_duty: shift.begins,
                      off_duty: shift.begins + 4.hours, additional_notes: "Mentored")
    Timesheet.create!(person: mentee, position: @gd_mentee, on_duty: shift.begins + 15.minutes,
                      off_duty: shift.begins + 4.hours, additional_notes: "Mentored")

    owed = SurveyUnansweredFinder.new(mentor.id, YEAR, Person::ACTIVE).call.sessions.sole

    assert_equal [shift.id, Survey::MENTOR_FOR_MENTEES, "Burn Night"], [owed.id, owed.type, owed.description]
    assert_equal [mentee.callsign], owed.mentoring.map(&:callsign)
  end
end
