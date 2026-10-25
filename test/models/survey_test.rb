# frozen_string_literal: true

require "test_helper"

# What a survey will and will not accept, who may manage one, and what
# duplicating one produces.
class SurveyTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include SurveyTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    setup_survey_positions
    setup_survey_managers
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # ==========================================================================
  # Who may manage surveys
  # ==========================================================================

  test "a survey role of any kind reaches the section" do
    assert Survey.can_manage_any?(@dirt_manager)
    assert Survey.can_manage_any?(@art_manager)
    assert Survey.can_manage_any?(@alpha_manager)
    assert_not Survey.can_manage_any?(@outsider)
    assert_not Survey.can_manage_any?(nil)
  end

  test "an admin reaches the section without a survey role" do
    admin = person(:auditor_ranger)
    grant_role(admin, Role::ADMIN)

    assert Survey.can_manage_any?(admin)
  end

  # ==========================================================================
  # The positions and kinds each person is offered
  # ==========================================================================

  test "the flat Survey Management role manages In-Person Training and nothing else" do
    positions = Survey.manageable_positions(@dirt_manager)

    assert_equal [@dirt.id], positions[:training].map(&:id)
    assert_empty positions[:mentor]
    assert_empty positions[:mentee]
    assert_empty positions[:alpha]
    assert_equal [Survey::TRAINING, Survey::TRAINER], Survey.type_options_for(@dirt_manager)
  end

  test "a training's survey role covers its mentors and mentees too" do
    positions = Survey.manageable_positions(@art_manager)

    assert_equal [@green_dot.id], positions[:training].map(&:id)
    assert_equal [@gd_mentor.id], positions[:mentor].map(&:id)
    assert_equal [@gd_mentee.id], positions[:mentee].map(&:id)
    assert_equal [Survey::TRAINING, Survey::TRAINER, Survey::MENTOR_FOR_MENTEES,
                  Survey::MENTEES_FOR_MENTOR],
                 Survey.type_options_for(@art_manager)
  end

  test "the Alpha survey role covers Alpha and the Mentor position" do
    positions = Survey.manageable_positions(@alpha_manager)

    assert_equal [@alpha.id], positions[:alpha].map(&:id)
    assert_equal [@mentor.id], positions[:mentor].map(&:id)
    assert_empty positions[:training]
    assert_includes Survey.type_options_for(@alpha_manager), Survey::ALPHA
    assert_not_includes Survey.type_options_for(@alpha_manager), Survey::TRAINING
  end

  test "someone with no survey role is offered nothing" do
    assert_empty Survey.type_options_for(@outsider)
  end

  # The Troubleshooters' mentee position is called "Prospective", so a rule
  # built on titles alone would leave that whole cadre unable to have one.
  test "a flagged ART mentee position is offered even when its title does not say so" do
    team = Team.create!(title: "Troubleshooter Team", active: true)
    Position.create!(id: Position::TROUBLESHOOTER_TRAINING, title: "Troubleshooter Training",
                     type: Position::TYPE_TRAINING, active: true, team:, has_art_mentoring: true)
    prospective = Position.create!(id: Position::TROUBLESHOOTER_MENTEE, title: "Troubleshooter Prospective",
                                   type: "Command", active: true, team:, is_art_mentee: true)

    assert Survey.position_in_category?(prospective.id, :mentee)
    assert_includes Survey.positions_in_category(:mentee).map(&:id), prospective.id
  end

  test "the trainer positions are not offered as training positions" do
    Position.create!(id: Position::GREEN_DOT_TRAINER, title: "Green Dot Trainer",
                     type: Position::TYPE_TRAINING, active: true)

    titles = Survey.positions_in_category(:training).map(&:title)

    assert_includes titles, "Green Dot Training"
    assert_not_includes titles, "Green Dot Trainer"
  end

  # ==========================================================================
  # Validations
  # ==========================================================================

  test "a survey needs a position, because one without it can be managed by no one" do
    survey = Survey.new(year: YEAR, type: Survey::TRAINING, title: "Feedback")

    assert_not survey.valid?
    assert_includes survey.errors.attribute_names, :position_id
  end

  test "the position has to match the kind of survey" do
    survey = Survey.new(year: YEAR, type: Survey::TRAINING, position_id: @gd_mentor.id,
                        title: "Feedback")

    assert_not survey.valid?
    assert_includes survey.errors.full_messages,
                    "Position must be a training position for this kind of survey"
  end

  test "a mentoring survey names the position it asks about, of the other kind" do
    survey = Survey.new(year: YEAR, type: Survey::MENTEES_FOR_MENTOR, position_id: @gd_mentee.id,
                        title: "Feedback")
    assert_not survey.valid?
    assert_includes survey.errors.full_messages, "About must name the position this survey asks about"

    survey.mentoring_position_id = @gd_mentee.id
    assert_not survey.valid?
    assert_includes survey.errors.full_messages,
                    "About must be a mentor position for this kind of survey"

    survey.mentoring_position_id = @gd_mentor.id
    assert survey.valid?, survey.errors.full_messages.to_sentence
  end

  test "changing a survey away from a mentoring kind drops what it asked about" do
    survey = create_survey(position: @gd_mentee, type: Survey::MENTEES_FOR_MENTOR,
                           mentoring_position: @gd_mentor)

    survey.update!(type: Survey::TRAINING, position_id: @green_dot.id)

    assert_nil survey.reload.mentoring_position_id
  end

  test "a survey saved elsewhere with another pairing can still be reworded" do
    # Both stacks share these rows, and the other one has no such rule. A
    # title fix should not be held up by a pairing this page did not make.
    survey = create_survey(position: @dirt)
    survey.update_columns(position_id: @gd_mentor.id)
    survey.reload

    assert survey.update(title: "A better title"), survey.errors.full_messages.to_sentence

    survey.type = Survey::TRAINER
    assert_not survey.valid?
  end

  test "a kind of survey this page does not know is refused" do
    survey = Survey.new(year: YEAR, type: "nonsense", position_id: @dirt.id, title: "Feedback")

    assert_not survey.valid?
    assert_includes survey.errors.full_messages,
                    "Who answers must be one of the kinds this page offers"
  end

  test "a survey saved without any text keeps empty text rather than failing" do
    survey = Survey.create!(year: YEAR, type: Survey::TRAINING, position_id: @dirt.id,
                            title: "Feedback")

    assert_equal "", survey.reload.prologue
    assert_equal "", survey.epilogue
  end

  # An editor nobody typed in still submits its empty block. Stored as it
  # arrived, the member's survey page would show an empty callout for a prologue
  # that was never written. What counts as empty is listed in document_test.rb;
  # this proves both columns are held to it.
  test "an editor left empty stores no text" do
    survey = create_survey(position: @dirt, prologue: "<p><br></p>",
                           epilogue: "<p><strong> </strong></p>")

    assert_equal "", survey.reload.prologue
    assert_equal "", survey.epilogue
  end

  test "text written in the editor is stored as it arrived" do
    survey = create_survey(position: @dirt, prologue: "<p>Tell us <strong>everything</strong>.</p>",
                           epilogue: "<ul><li>Thanks</li></ul>")

    assert_equal "<p>Tell us <strong>everything</strong>.</p>", survey.reload.prologue
    assert_equal "<ul><li>Thanks</li></ul>", survey.epilogue
  end

  # ==========================================================================
  # Where the answers are read
  # ==========================================================================

  test "a training survey's answers are read under that training" do
    survey = create_survey(position: @dirt)

    assert_equal @dirt, survey.feedback_training_position
  end

  test "a cadre survey's answers are read under the training the cadre belongs to" do
    survey = create_survey(position: @gd_mentee, type: Survey::MENTEES_FOR_MENTOR,
                           mentoring_position: @gd_mentor)

    assert_equal @green_dot, survey.feedback_training_position
  end

  # The Mentor position walks back to Alpha, which is a cadre rather than a
  # training and has no page -- a link built from it would go nowhere.
  test "a survey whose cadre belongs to no training is read nowhere" do
    survey = create_survey(position: @mentor, type: Survey::MENTOR_FOR_MENTEES,
                           mentoring_position: @gd_mentee)

    assert_nil survey.feedback_training_position
  end

  # ==========================================================================
  # Duplicating
  # ==========================================================================

  test "a duplicate carries the groups and questions across, switched off" do
    survey = create_survey(position: @dirt, year: YEAR - 1, active: true,
                           title: "#{YEAR - 1} Ranger Training Feedback")
    venue = create_survey_group(survey, title: "The Venue", sort_index: 1)
    trainers = create_survey_group(survey, title: "Your Trainers",
                                   type: SurveyGroup::TYPE_TRAINER, sort_index: 4)
    create_survey_question(survey, venue, description: "Rate the venue",
                                          type: SurveyQuestion::TYPE_RATING, summarize_rating: true)
    create_survey_question(survey, trainers, description: "Rate this trainer",
                                             type: SurveyQuestion::TYPE_RATING)

    copy = survey.duplicate_into(YEAR)

    assert_equal YEAR, copy.year
    assert_not copy.active
    assert_equal "#{YEAR} Ranger Training Feedback", copy.title
    assert_equal ["The Venue", "Your Trainers"], copy.survey_groups.map(&:title)
    assert_equal [SurveyGroup::TYPE_NORMAL, SurveyGroup::TYPE_TRAINER],
                 copy.survey_groups.map(&:type)
    assert_equal ["Rate the venue", "Rate this trainer"],
                 copy.survey_groups.flat_map { |g| g.survey_questions.map(&:description) }
    assert copy.survey_groups.first.survey_questions.first.summarize_rating
    assert_empty copy.survey_groups.map(&:id) & survey.survey_groups.map(&:id)
  end

  test "a duplicate of a title with no year in it keeps the title" do
    survey = create_survey(position: @dirt, year: YEAR - 1, title: "Ranger Training Feedback")

    assert_equal "Ranger Training Feedback", survey.duplicate_into(YEAR).title
  end

  test "duplicating leaves no half-made copy behind when a row will not save" do
    survey = create_survey(position: @dirt, year: YEAR - 1)
    group = create_survey_group(survey, title: "The Venue")
    create_survey_question(survey, group, description: "Rate it")
    # A group that was saved before the rule existed, which the copy cannot
    # pass: the copy is a new record, so it is checked.
    group.update_columns(type: SurveyGroup::TYPE_SUMMARY, report_title: "")

    assert_no_difference ["Survey.count", "SurveyGroup.count", "SurveyQuestion.count"] do
      assert_raises(ActiveRecord::RecordInvalid) { survey.duplicate_into(YEAR) }
    end
  end

  # ==========================================================================
  # Deleting
  # ==========================================================================

  test "deleting a survey clears everything filed under it" do
    survey = create_survey(position: @dirt)
    group = create_survey_group(survey)
    question = create_survey_question(survey, group)
    create_survey_answer(question, person: @outsider)

    survey.destroy!

    assert_empty SurveyGroup.where(survey_id: survey.id)
    assert_empty SurveyQuestion.where(survey_id: survey.id)
    assert_empty SurveyAnswer.where(survey_id: survey.id)
  end
end
