# frozen_string_literal: true

require "test_helper"

# How ArtMentoring::PersonHistory files a person's ART walks: one section per
# ART with a cohort per year, the ART and year taken from the mentee entry as
# the roster files them, and the fallbacks once the entry or position is gone.
class ArtMentoring::PersonHistoryTest < ActiveSupport::TestCase
  include ArtMentoringTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 9, 3, 12, 0, 0)
    Current.reset
    setup_art_mentoring
    @mentee = create_person("Tinsel")
    @mentor = create_person("Ferrous")
    @first = mentee_entry(@mentee, Time.zone.local(YEAR, 9, 1, 18, 0, 0))
    @second = mentee_entry(@mentee, Time.zone.local(YEAR, 9, 2, 18, 0, 0))
    [@first, @second].each { |entry| walk(entry, @mentor) }
  end

  def history(person) = ArtMentoring::PersonHistory.new(person.id)

  test "a mentee's walks are one section per ART, a cohort per year, newest shift first" do
    sections = history(@mentee).sections

    assert_equal 1, sections.size
    section = sections.first
    assert_equal @training, section.training
    assert_equal "Green Dot Training", section.title
    assert_equal [YEAR], section.as_mentee.map(&:year)
    cohort = section.as_mentee.first
    assert_equal [@second.on_duty, @first.on_duty], cohort.rows.map(&:on_duty)
    assert_equal [@mentor], cohort.rows.map(&:other).uniq
    assert_empty section.as_mentor
    assert_equal 2, history(@mentee).shift_count
  end

  test "a mentor's cohort counts mentees, not walks, and tallies the results" do
    walk(mentee_entry(create_person("Moonrake"), Time.zone.local(YEAR, 9, 2, 18, 0, 0)), @mentor,
         status: PersonMentor::STATUS_BONK)

    cohort = history(@mentor).sections.first.as_mentor.first
    assert_equal 3, cohort.rows.size
    assert_equal 2, cohort.mentee_count
    assert_equal [0, 1, 2], [cohort.passed, cohort.bonked, cohort.pending]
    assert_equal [false, false, false], cohort.rows.map(&:can_message?) # none has signed in
  end

  test "Alpha walks are left out" do
    # active_ranger has Alpha rows as mentee and mentor in the fixtures.
    assert_empty history(person(:active_ranger)).sections
  end

  test "a walk whose entry was deleted sorts last, under its mentor_year" do
    @first.delete

    cohort = history(@mentee).sections.first.as_mentee.first
    assert_equal YEAR, cohort.year
    assert_equal [@second.on_duty, nil], cohort.rows.map(&:on_duty)
  end

  test "a walk follows its entry onto another ART's mentee position" do
    sanctuary = Position.create!(id: Position::SANCTUARY, title: "Sanctuary Training", type: Position::TYPE_TRAINING,
                                 active: true, team: teams(:dirt_team), has_art_mentoring: true)
    Position.create!(id: Position::SANCTUARY_MENTEE, title: "Sanctuary Mentee", type: Position::TYPE_FRONTLINE,
                     active: true, team: teams(:dirt_team), is_art_mentee: true)
    @second.update_columns(position_id: Position::SANCTUARY_MENTEE)

    sections = history(@mentee).sections
    assert_equal ["Green Dot Training", "Sanctuary Training"], sections.map(&:title)
    assert_equal sanctuary, sections.last.training
    assert_equal [@second.on_duty], sections.last.as_mentee.first.rows.map(&:on_duty)
  end

  test "a walk takes its entry's year once the entry moves" do
    @second.update_columns(on_duty: @second.on_duty + 1.year, off_duty: nil)

    assert_equal [YEAR + 1, YEAR], history(@mentee).sections.first.as_mentee.map(&:year)
  end

  test "a position whose team lost its training is titled by the position" do
    @training.update_columns(has_art_mentoring: false)

    section = history(@mentee).sections.first
    assert_nil section.training
    assert_equal "Green Dot Mentee", section.title
  end

  test "walks under a deleted position row are kept, titled by its id" do
    [@first, @second].each(&:delete)
    Position.where(id: @mentee_position.id).delete_all

    section = history(@mentee).sections.first
    assert_nil section.training
    assert_equal "Position ##{Position::GREEN_DOT_MENTEE}", section.title
    assert_equal 2, section.as_mentee.first.rows.size
  end
end
