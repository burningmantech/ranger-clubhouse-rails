# frozen_string_literal: true

require "test_helper"

class TeamMembershipReportTest < ActiveSupport::TestCase
  setup do
    Current.reset
    @team = teams(:dirt_team)

    # Positions are built here rather than in the fixtures: the grid turns on
    # team_category and on the training/trainer split, and no fixture position
    # carries either. The trainer column has to take a real id out of
    # Position::TRAINERS -- that constant is how the report tells "taught" from
    # "trained", and it names ids, not attributes.
    @recommended = create_position("Dirt Patrol", Position::TEAM_CATEGORY_ALL_MEMBERS)
    @optional = create_position("Dirt Lead", Position::TEAM_CATEGORY_OPTIONAL)
    @trainer = create_position("Green Dot Trainer", Position::TEAM_CATEGORY_OPTIONAL,
                               id: Position::GREEN_DOT_TRAINER, type: Position::TYPE_TRAINING)
    @training = create_position("Dirt Training", Position::TEAM_CATEGORY_PUBLIC,
                                type: Position::TYPE_TRAINING)

    @member = person(:active_ranger)
    @grantee = person(:retired_ranger)
    @public_only = person(:auditor_ranger)
    @stranger = person(:bonked_ranger)

    PersonTeam.create!(team_id: @team.id, person_id: @member.id)
  end

  teardown { Current.reset }

  test "the roster is the team's members plus its Recommended and Optional grantees" do
    grant(@grantee, @optional)
    grant(@public_only, @training)

    callsigns = report.people.map(&:callsign)

    assert_includes callsigns, @member.callsign
    assert_includes callsigns, @grantee.callsign
    assert_not_includes callsigns, @stranger.callsign
  end

  # A public position is open to the whole organization. Counting its holders
  # would bury the team's own roster under hundreds of strangers.
  test "someone whose only tie is a public position is left off the roster" do
    grant(@public_only, @training)

    assert_not_includes report.people.map(&:callsign), @public_only.callsign
  end

  test "a member's public grant is still shown once they are on the roster" do
    grant(@member, @training)

    assert_not_nil find_person(@member).grant(@training.id)
  end

  test "columns are grouped by category and ordered by title within a group" do
    result = report

    assert_equal [@recommended.id], result.position_ids_in(Position::TEAM_CATEGORY_ALL_MEMBERS)
    assert_equal [@optional.id, @trainer.id], result.position_ids_in(Position::TEAM_CATEGORY_OPTIONAL)
    assert_equal [@training.id], result.position_ids_in(Position::TEAM_CATEGORY_PUBLIC)
  end

  test "people are listed by callsign" do
    grant(@grantee, @optional)

    callsigns = report.people.map(&:callsign)

    assert_equal callsigns.sort_by(&:downcase), callsigns
  end

  # ------------------------------------------------------------ grant detail

  test "a normal position reports the last year the person rangered it" do
    grant(@member, @recommended)
    add_timesheet(@member, @recommended, 2023)
    add_timesheet(@member, @recommended, 2025)

    assert_equal 2025, find_person(@member).grant(@recommended.id).year
  end

  test "a training position reports the last year the person passed it" do
    grant(@member, @training)
    add_trainee_status(@member, @training, 2024, status: TraineeStatus::STATUS_PASSED)

    assert_equal 2024, find_person(@member).grant(@training.id).year
  end

  test "a failed training session is not a year trained" do
    grant(@member, @training)
    add_trainee_status(@member, @training, 2024, status: TraineeStatus::STATUS_NOT_PASSED)

    assert_nil find_person(@member).grant(@training.id).year
  end

  test "a trainer position reports the last year the person taught it" do
    grant(@member, @trainer)
    add_trainer_status(@member, @trainer, 2024, status: TrainerStatus::STATUS_ATTENDED)

    assert_equal 2024, find_person(@member).grant(@trainer.id).year
  end

  test "a trainer who did not attend has no year taught" do
    grant(@member, @trainer)
    add_trainer_status(@member, @trainer, 2024, status: TrainerStatus::STATUS_NO_SHOW)

    assert_nil find_person(@member).grant(@trainer.id).year
  end

  # Deep Desert Patrol Trainer teaches sessions but its team carries no trainee
  # position, so no key in Position::TRAINERS can ever name it. Read as a
  # trainee it would be measured against trainee_status rows for a trainer's
  # slots -- a query that cannot match -- and the cell would read "never trained
  # at" where the truth is "never taught".
  test "a trainer position absent from Position::TRAINERS is still measured against teaching" do
    unmapped = create_position("Deep Desert Patrol Trainer", Position::TEAM_CATEGORY_OPTIONAL,
                               type: Position::TYPE_TRAINING)
    grant(@member, unmapped)
    add_trainer_status(@member, unmapped, 2024, status: TrainerStatus::STATUS_ATTENDED)

    assert_not_includes TeamMembershipReport::TRAINER_POSITION_IDS, unmapped.id
    assert_equal TeamMembershipReport::KIND_TAUGHT, report.column(unmapped.id).kind
    assert_equal 2024, find_person(@member).grant(unmapped.id).year
  end

  # A timesheet against a training position is not a session attended, and the
  # grid must not report it as one -- the column heading says "trained".
  test "a timesheet does not count as a year trained" do
    grant(@member, @training)
    add_timesheet(@member, @training, 2025)

    assert_nil find_person(@member).grant(@training.id).year
  end

  test "the joined date comes from the open position log row" do
    grant(@member, @recommended)
    PersonPositionLog.create!(person_id: @member.id, position_id: @recommended.id,
                              joined_on: Date.new(2024, 8, 25))

    assert_equal Date.new(2024, 8, 25), find_person(@member).grant(@recommended.id).joined_on.to_date
  end

  # A closed row is a grant that was revoked and later re-made. Reading it
  # would date the current grant to the one that ended.
  test "a closed position log row is not the joined date" do
    grant(@member, @recommended)
    PersonPositionLog.create!(person_id: @member.id, position_id: @recommended.id,
                              joined_on: Date.new(2019, 1, 1), left_on: Date.new(2020, 1, 1))

    assert_nil find_person(@member).grant(@recommended.id).joined_on
  end

  test "an ungranted position has no grant at all" do
    assert_nil find_person(@member).grant(@optional.id)
  end

  # ----------------------------------------------------------- person totals

  test "last_year is the most recent year across every position on the team" do
    grant(@member, @recommended)
    grant(@member, @optional)
    add_timesheet(@member, @recommended, 2021)
    add_timesheet(@member, @optional, 2024)

    assert_equal 2024, find_person(@member).last_year
  end

  test "last_year is nil for someone who never rangered anything on the team" do
    grant(@member, @recommended)

    assert_nil find_person(@member).last_year
  end

  # Upstream's rule, kept: the "never rangered" views must also surface people
  # who hold none of the category's positions, not only idle grantees.
  test "rangered_any? is false when the person holds none of the positions" do
    assert_not find_person(@member).rangered_any?([@optional.id])
  end

  test "rangered_any? is false for a grant that was never used" do
    grant(@member, @optional)

    assert_not find_person(@member).rangered_any?([@optional.id])
  end

  # ------------------------------------------------------------ column tally

  test "column counts cover only the people on the roster" do
    grant(@member, @recommended)
    add_timesheet(@member, @recommended, 2025)
    grant(@public_only, @recommended) # a grantee joins the roster through it
    grant(@stranger, @training) # public only -- off the roster entirely

    result = report
    recommended = result.columns.find { |column| column.id == @recommended.id }
    training = result.columns.find { |column| column.id == @training.id }

    assert_equal 2, recommended.granted_count
    assert_equal 1, recommended.never_count
    assert_equal 0, training.granted_count, "the stranger's public grant must not be counted"
  end

  test "member_count and never_rangered_count describe the roster" do
    grant(@grantee, @optional)
    add_timesheet(@grantee, @optional, 2025)

    result = report

    assert_equal 2, result.people.size
    assert_equal 1, result.member_count
    assert_equal 1, result.never_rangered_count
  end

  # --------------------------------------------------------- revocable rules

  test "revocable positions are the Recommended and Optional ones" do
    ids = TeamMembershipReport.revocable_position_ids(@team)

    assert_equal [@recommended.id, @optional.id, @trainer.id].sort, ids.sort
  end

  private

  def report = TeamMembershipReport.execute(@team)

  def find_person(person) = report.people.find { |row| row.id == person.id }

  def create_position(title, category, id: nil, type: nil)
    Position.create!(id:, title:, team_id: @team.id, team_category: category, type:, active: true)
  end

  def grant(person, position)
    PersonPosition.create!(person_id: person.id, position_id: position.id)
  end

  def add_timesheet(person, position, year)
    Timesheet.create!(person_id: person.id, position_id: position.id,
                      on_duty: Time.zone.local(year, 8, 25, 10, 0),
                      off_duty: Time.zone.local(year, 8, 25, 14, 0),
                      additional_notes: "roster report test")
  end

  def add_trainee_status(person, position, year, status:)
    slot = create_slot(position, year)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
    TraineeStatus.create!(person_id: person.id, slot_id: slot.id, status:)
  end

  def add_trainer_status(person, position, year, status:)
    slot = create_slot(position, year)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
    TrainerStatus.create!(person_id: person.id, slot_id: slot.id, trainer_slot_id: slot.id, status:)
  end

  def create_slot(position, year)
    Slot.create!(position_id: position.id, begins: Time.zone.local(year, 8, 20, 9, 0),
                 ends: Time.zone.local(year, 8, 20, 13, 0), max: 10,
                 description: "#{position.title} #{year}", active: true)
  end
end
