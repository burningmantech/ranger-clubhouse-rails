# frozen_string_literal: true

require "test_helper"

# What Me › Trainer/Mentor Feedback reads: one person's feedback a year at a
# time, folded from the shapes SurveyBuilder reports it in, and never naming
# who wrote it.
class TrainerFeedbackReportTest < ActiveSupport::TestCase
  include SurveyTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    setup_survey_positions
    @trainer = person(:active_ranger)
    @other_trainer = person(:echelon_ranger)
    @trainee = person(:auditor_ranger)
    @bay = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 6, 9), description: "Bay Area, CA")
    @reno = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 21, 10), description: "Reno, NV")
  end

  # A trainees' survey: a venue group, and a trainer group asking about each
  # trainer -- one ranked rating, one plain rating, one comment question.
  def trainee_survey(year: YEAR)
    survey = create_survey(position: @dirt, year:)
    venue = create_survey_group(survey, title: "The Venue")
    group = create_survey_group(survey, title: "Your Trainers", type: SurveyGroup::TYPE_TRAINER)
    {
      survey:,
      venue_comment: create_survey_question(survey, venue, description: "What about the venue?"),
      ranked: create_survey_question(survey, group, description: "Rate your trainer overall",
                                                    type: SurveyQuestion::TYPE_RATING, summarize_rating: true),
      rating: create_survey_question(survey, group, description: "The trainer kept time",
                                                    type: SurveyQuestion::TYPE_RATING),
      comment: create_survey_question(survey, group, description: "What did this trainer do well?")
    }
  end

  test "years lists only the years with feedback about the person, newest first" do
    [2024, YEAR].each do |year|
      create_survey_answer(trainee_survey(year:)[:comment], person: @trainee, trainer: @trainer)
    end
    create_survey_answer(trainee_survey(year: 2025)[:comment], person: @trainee, trainer: @other_trainer)

    assert_equal [YEAR, 2024], TrainerFeedbackReport.years(@trainer.id)
    assert_empty TrainerFeedbackReport.for_year(@trainer.id, 2025)
  end

  test "a trainees' survey folds into ranked and plain ratings, then comments by session" do
    built = trainee_survey
    create_survey_answer(built[:ranked], person: @trainee, trainer: @trainer, slot: @bay, response: "7")
    create_survey_answer(built[:ranked], person: person(:alpha_ranger), trainer: @trainer, slot: @reno, response: "5")
    create_survey_answer(built[:rating], person: @trainee, trainer: @trainer, slot: @bay, response: "6")
    create_survey_answer(built[:comment], person: @trainee, trainer: @trainer, slot: @bay, response: "Great radio drill.")
    create_survey_answer(built[:comment], person: person(:alpha_ranger), trainer: @trainer, slot: @reno,
                                          response: "Calm and clear.")
    create_survey_answer(built[:comment], person: @trainee, trainer: @other_trainer, slot: @bay, response: "Not you.")
    create_survey_answer(built[:venue_comment], person: @trainee, slot: @bay, response: "The room was warm.")

    row = TrainerFeedbackReport.for_year(@trainer.id, YEAR).sole

    assert_equal built[:survey], row.survey
    assert_equal [["Rate your trainer overall", 6.0, 2], ["The trainer kept time", 6.0, 1]],
                 row.ratings.map { |rating| [rating.description, rating.stats.mean, rating.stats.rating_count] }
    question = row.questions.sole
    assert_equal "What did this trainer do well?", question.description
    assert_equal [[@bay.id, ["Great radio drill."]], [@reno.id, ["Calm and clear."]]],
                 question.groups.map { |slot, answers| [slot.slot_id, answers.map(&:answer)] }
    assert_equal [2, 3], [row.comment_count, row.rating_count]
    assert_equal [@bay.id, @reno.id], row.session_ids.sort
  end

  test "no answer says who wrote it, even one its writer agreed to share by name" do
    built = trainee_survey
    # The helper records every answer as shared by name.
    create_survey_answer(built[:comment], person: @trainee, trainer: @trainer, slot: @bay)

    answer = TrainerFeedbackReport.for_year(@trainer.id, YEAR).sole.questions.sole.groups.sole.last.sole

    assert answer.answer.present?
    assert_nil answer.person
  end

  test "a trainer-on-trainer survey ranks the person's own sessions" do
    survey = create_survey(position: @dirt, type: Survey::TRAINER, title: "#{YEAR} Trainer Feedback")
    group = create_survey_group(survey, title: "Your Fellow Trainers")
    ranked = create_survey_question(survey, group, description: "Rate this trainer",
                                                   type: SurveyQuestion::TYPE_RATING, summarize_rating: true)
    comment = create_survey_question(survey, group, description: "Feedback for this trainer?")
    create_survey_answer(ranked, person: @other_trainer, trainer: @trainer, slot: @bay, response: "7")
    create_survey_answer(ranked, person: @other_trainer, trainer: @trainer, slot: @reno, response: "5")
    create_survey_answer(comment, person: @other_trainer, trainer: @trainer, slot: @reno, response: "Easy to teach with.")

    row = TrainerFeedbackReport.for_year(@trainer.id, YEAR).sole

    assert_equal [[@bay.id, 7.0], [@reno.id, 5.0]],
                 row.ratings.map { |rating| [rating.slot_response.slot_id, rating.stats.mean] }
    assert_equal [[@reno.id, ["Easy to teach with."]]],
                 row.questions.sole.groups.map { |slot, answers| [slot.slot_id, answers.map(&:answer)] }
  end

  test "a multiple-choice question is tallied in the order its options were offered, not kept as comments" do
    survey = create_survey(position: @alpha, type: Survey::ALPHA, title: "Alpha Day Survey")
    group = create_survey_group(survey, title: "Your Mentors", type: SurveyGroup::TYPE_TRAINER)
    engagement = create_survey_question(survey, group, description: "Their engagement with you?",
                                                       type: SurveyQuestion::TYPE_OPTIONS, options: "Great\nOK\nTerrible")
    comment = create_survey_question(survey, group, description: "What did your mentor do well?")
    %w[OK Meh OK Great Fine].each do |pick|
      create_survey_answer(engagement, person: person(:alpha_ranger), trainer: @trainer, response: pick)
    end
    create_survey_answer(comment, person: person(:alpha_ranger), trainer: @trainer, response: "Patient with me.")

    row = TrainerFeedbackReport.for_year(@trainer.id, YEAR).sole

    choice = row.choices.sole
    assert_equal "Their engagement with you?", choice.description
    # The offered order, not the count order. "Meh" and "Fine" are no longer
    # options, so they go last, tied and in text order; nobody picked "Terrible".
    assert_equal [["Great", 1], ["OK", 2], ["Fine", 1], ["Meh", 1]], choice.tally.to_a
    assert_equal ["What did your mentor do well?"], row.questions.map(&:description)
    assert_equal [1, 5], [row.comment_count, row.choice_count]
  end

  # Me::SurveysController files every group of a trainer-on-trainer survey under
  # the trainer rated, so a summary-only group reaches this page too, as
  # SurveyBuilder::QuestionResponse objects.
  test "a multiple-choice question in a summary-only group is tallied like any other" do
    survey = create_survey(position: @dirt, type: Survey::TRAINER, title: "#{YEAR} Trainer Feedback")
    group = create_survey_group(survey, title: "Overall", type: SurveyGroup::TYPE_SUMMARY, report_title: "Overall")
    ready = create_survey_question(survey, group, description: "Ready to lead a session?",
                                                  type: SurveyQuestion::TYPE_OPTIONS, options: "Yes\nNo\nMaybe")
    %w[Maybe Yes Yes].each do |pick|
      create_survey_answer(ready, person: @other_trainer, trainer: @trainer, slot: @bay, response: pick)
    end

    row = TrainerFeedbackReport.for_year(@trainer.id, YEAR).sole

    assert_equal [["Yes", 2], ["Maybe", 1]], row.choices.sole.tally.to_a
  end

  test "a trainer-on-trainer survey rated without a comment still shows its ranked ratings" do
    survey = create_survey(position: @dirt, type: Survey::TRAINER, title: "#{YEAR} Trainer Feedback")
    group = create_survey_group(survey, title: "Your Fellow Trainers")
    ranked = create_survey_question(survey, group, description: "Rate this trainer",
                                                   type: SurveyQuestion::TYPE_RATING, summarize_rating: true)
    create_survey_question(survey, group, description: "Feedback for this trainer?")
    create_survey_answer(ranked, person: @other_trainer, trainer: @trainer, slot: @bay, response: "6")

    row = TrainerFeedbackReport.for_year(@trainer.id, YEAR).sole

    assert_equal [[@bay.id, 6.0]], row.ratings.map { |rating| [rating.slot_response.slot_id, rating.stats.mean] }
    assert_empty row.questions
  end

  test "every session the feedback came from counts, not only those with a comment" do
    built = trainee_survey
    create_survey_answer(built[:rating], person: @trainee, trainer: @trainer, slot: @reno, response: "6")
    create_survey_answer(built[:comment], person: @trainee, trainer: @trainer, slot: @bay, response: "Clear.")

    row = TrainerFeedbackReport.for_year(@trainer.id, YEAR).sole

    assert_equal [@bay.id, @reno.id], row.session_ids.sort
  end

  test "blank answers and mentors' assessments of a mentee are not feedback to list" do
    create_survey_answer(trainee_survey(year: 2025)[:comment], person: @trainee, trainer: @trainer, response: "")
    assessment = create_survey(position: @gd_mentor, type: Survey::MENTOR_FOR_MENTEES, mentoring_position: @gd_mentee)
    group = create_survey_group(assessment, title: "Your Mentees", type: SurveyGroup::TYPE_TRAINER)
    create_survey_answer(create_survey_question(assessment, group), person: @other_trainer, trainer: @trainer)

    assert_empty TrainerFeedbackReport.years(@trainer.id)
    assert_not TrainerFeedbackReport.any_for?(@trainer.id)

    create_survey_answer(trainee_survey[:comment], person: @trainee, trainer: @trainer, slot: @bay)

    assert_equal [YEAR], TrainerFeedbackReport.years(@trainer.id)
    assert TrainerFeedbackReport.any_for?(@trainer.id)
  end

  test "an Alpha survey's comments come back without a session" do
    survey = create_survey(position: @alpha, type: Survey::ALPHA, title: "Alpha Day Survey")
    group = create_survey_group(survey, title: "Your Mentors", type: SurveyGroup::TYPE_TRAINER)
    comment = create_survey_question(survey, group, description: "What did your mentor do well?")
    create_survey_answer(comment, person: person(:alpha_ranger), trainer: @trainer, response: "Patient with me.")

    row = TrainerFeedbackReport.for_year(@trainer.id, YEAR).sole

    assert_equal [[nil, ["Patient with me."]]],
                 row.questions.sole.groups.map { |slot, answers| [slot, answers.map(&:answer)] }
    assert_empty row.session_ids
  end
end
