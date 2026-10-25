# frozen_string_literal: true

# test_helper loads test/support alphabetically, so this file comes first.
require_relative "training_slot_test_helper"

# Green Dot as an ART mentoring training, for the mentoring pages' tests: the
# training and its mentor and mentee positions on the Green Dot cadre, and
# builders for their shifts and timesheet entries. Positions are created rather
# than fixtured because the rules key on the ids the Clubhouse names in code.
module ArtMentoringTestHelper
  include TrainingSlotTestHelper

  def setup_art_mentoring
    team = teams(:green_dot_cadre)
    @training = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                 type: Position::TYPE_TRAINING, active: true, team:, has_art_mentoring: true)
    @mentor_position = Position.create!(id: Position::GREEN_DOT_MENTOR, title: "Green Dot Mentor",
                                        type: Position::TYPE_FRONTLINE, active: true, team:, is_art_mentor: true)
    @mentee_position = Position.create!(id: Position::GREEN_DOT_MENTEE, title: "Green Dot Mentee",
                                        type: Position::TYPE_FRONTLINE, active: true, team:, is_art_mentee: true)
  end

  def mentee_shift(begins) = create_slot(@mentee_position, begins:, ends: begins + 6.hours, description: "Mentee")

  def mentor_shift(begins) = create_slot(@mentor_position, begins:, ends: begins + 6.hours, description: "Mentor")

  # A timesheet entry. `slot:` names its shift; left out, Timesheet's own
  # lookup may attach one, and `loose: true` clears whatever it attached.
  def entry(person, position, on_duty, off_duty: nil, slot: nil, loose: false)
    attributes = { person_id: person.id, position_id: position.id, on_duty:, off_duty:, additional_notes: "signed in" }
    attributes[:slot_id] = slot.id if slot
    Timesheet.create!(**attributes).tap { |sheet| sheet.update_column(:slot_id, nil) if loose }
  end

  def mentee_entry(person, on_duty, **) = entry(person, @mentee_position, on_duty, **)

  def mentor_entry(person, on_duty, **) = entry(person, @mentor_position, on_duty, **)

  def hold_mentor_position(*people)
    people.each { |person| PersonPosition.create!(person_id: person.id, position_id: @mentor_position.id) }
  end

  def hold_mentee_position(person) = PersonPosition.create!(person_id: person.id, position_id: @mentee_position.id)

  # A position on the training's team that a membership brings with it.
  def recommended_position(title)
    Position.create!(title:, type: Position::TYPE_FRONTLINE, active: true, team: @training.team,
                     team_category: Position::TEAM_CATEGORY_ALL_MEMBERS)
  end

  def walk(mentee_entry, mentor, status: PersonMentor::STATUS_PENDING, notes: nil)
    PersonMentor.create!(person_id: mentee_entry.person_id, mentor:, mentor_year: mentee_entry.on_duty.year,
                         position_id: @mentee_position.id, timesheet_id: mentee_entry.id, status:, notes:)
  end
end
