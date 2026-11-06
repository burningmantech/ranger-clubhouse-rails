# frozen_string_literal: true

require "test_helper"

# Me › Trainer/Mentor Feedback: a year of what others said about the reader,
# never who said it, and a menu item only for someone with feedback.
class Me::FeedbackControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include SurveyTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    setup_survey_positions
    @trainer = person(:active_ranger)
    @trainee = person(:auditor_ranger)
  end

  # A trainees' survey whose trainer group asks one rating and one comment
  # question, and a session in its year to answer them after.
  def trainee_survey(year: YEAR)
    survey = create_survey(position: @dirt, year:)
    group = create_survey_group(survey, title: "Your Trainers", type: SurveyGroup::TYPE_TRAINER)
    {
      survey:,
      session: create_slot(@dirt, begins: Time.zone.local(year, 6, 6, 9), description: "Bay Area, CA"),
      rating: create_survey_question(survey, group, description: "Rate your trainer", type: SurveyQuestion::TYPE_RATING),
      comment: create_survey_question(survey, group, description: "What did this trainer do well?")
    }
  end

  test "lists the year's feedback without saying who wrote it" do
    built = trainee_survey
    create_survey_answer(built[:rating], person: @trainee, trainer: @trainer, slot: built[:session], response: "6")
    create_survey_answer(built[:comment], person: @trainee, trainer: @trainer, slot: built[:session],
                                          response: "Made the radio drill stick.")

    sign_in_as(@trainer)
    get me_feedback_path

    assert_response :success
    assert_select "h1", text: %r{Trainer/Mentor Feedback}
    assert_select "#survey-#{built[:survey].id}", text: /#{built[:survey].title}/
    assert_select "#survey-#{built[:survey].id} th[scope=row]", text: /Rate your trainer/
    assert_match "Made the radio drill stick.", response.body
    assert_match "Bay Area, CA", response.body
    # The answer is stored as shareable; this page still never names who wrote it.
    assert_not_includes response.body, @trainee.callsign
    assert_select "a[href=?]", me_feedback_path, text: "Trainer/Mentor Feedback"
    # No multiple-choice question was answered, so the year has no box for one.
    assert_select "#feedback-stats div", text: "Multiple-Choice Answers", count: 0
  end

  test "multiple-choice answers are tallied in a table of their own, not counted as comments" do
    built = trainee_survey
    group = SurveyGroup.find(built[:comment].survey_group_id)
    on_time = create_survey_question(built[:survey], group, description: "Did they keep time?",
                                                            type: SurveyQuestion::TYPE_OPTIONS, options: "Yes\nNo")
    %w[No Yes Yes].each do |pick|
      create_survey_answer(on_time, person: @trainee, trainer: @trainer, slot: built[:session], response: pick)
    end
    create_survey_answer(built[:comment], person: @trainee, trainer: @trainer, slot: built[:session],
                                          response: "Clear and calm.")

    sign_in_as(@trainer)
    get me_feedback_path

    assert_response :success
    assert_select "#survey-#{built[:survey].id} th[scope=row]", text: /Did they keep time\?/
    assert_select "#survey-#{built[:survey].id} td", text: /Yes ×2 · No ×1/
    assert_match "1 comment · 3 multiple-choice answers · 1 session", response.body
    # The picks have a box of their own, and the unanswered rating question none.
    assert_select "#feedback-stats > div", text: /\A3\s*Multiple-Choice Answers\z/
    assert_select "#feedback-stats div", text: "Ratings", count: 0
  end

  test "offers only the years with feedback, and any other year opens the latest" do
    [2024, YEAR].each do |year|
      built = trainee_survey(year:)
      create_survey_answer(built[:comment], person: @trainee, trainer: @trainer, slot: built[:session],
                                            response: "Said in #{year}.")
    end

    sign_in_as(@trainer)
    # 2019 holds nothing, and an array is no year at all.
    [{ year: 2019 }, { year: ["2024"] }].each do |params|
      get me_feedback_path(params)

      assert_response :success
      assert_equal %w[2026 2024], css_select("#year-selector option").map { |option| option["value"] }
      assert_select "#year-selector option[selected]", text: "2026"
      assert_match "Said in 2026.", response.body
    end

    get me_feedback_path(year: 2024)

    assert_match "Said in 2024.", response.body
    assert_no_match(/Said in 2026\./, response.body)
  end

  test "with no year asked for, the page opens on the newest year with something to show" do
    older = trainee_survey(year: 2025)
    create_survey_answer(older[:comment], person: @trainee, trainer: @trainer, slot: older[:session],
                                          response: "Said in 2025.")
    # An answer on a session deleted since: its slot is gone, so no report can place it.
    create_survey_answer(trainee_survey[:comment], person: @trainee, trainer: @trainer, response: "Orphaned.")

    sign_in_as(@trainer)
    get me_feedback_path

    assert_response :success
    assert_select "#year-selector option[selected]", text: "2025"
    assert_match "Said in 2025.", response.body
  end

  test "someone with no feedback gets the empty state, and no menu item" do
    sign_in_as(person(:echelon_ranger))
    get me_feedback_path

    assert_response :success
    assert_match "No feedback yet.", response.body
    assert_select "#year-selector", count: 0
    assert_select "a[href=?]", me_feedback_path, count: 0
  end

  test "jump links to each survey appear once the year holds more than one" do
    built = trainee_survey
    create_survey_answer(built[:comment], person: @trainee, trainer: @trainer, slot: built[:session])

    sign_in_as(@trainer)
    get me_feedback_path

    assert_select "nav[aria-label=?]", "#{YEAR} surveys", count: 0

    peers = create_survey(position: @dirt, type: Survey::TRAINER, title: "#{YEAR} Trainer Feedback")
    group = create_survey_group(peers, title: "Your Fellow Trainers")
    create_survey_answer(create_survey_question(peers, group), person: person(:echelon_ranger), trainer: @trainer,
                                                               slot: built[:session])
    get me_feedback_path

    assert_select "nav[aria-label=?] a", "#{YEAR} surveys", count: 2
    assert_select "nav a[href=?]", "#survey-#{peers.id}", text: /#{peers.title}/
  end
end
