# frozen_string_literal: true

require "test_helper"

# Mentoring > Alpha Surveys: the survey-management gate (tighter than the
# section's own Mentor gate), the all-years index, the report and per-mentor
# pages, and the two exports.
class Mentoring::SurveysControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  # A built survey and the questions a test needs to answer.
  Built = Struct.new(:survey, :overall_rating, :overall_comment,
                     :mentor_group, :mentor_rating, :mentor_comment, keyword_init: true) do
    def id = survey.id
  end

  setup do
    travel_to Time.zone.local(YEAR, 10, 1, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @alpha = Position.create!(id: Position::ALPHA, title: "Alpha", type: "Frontline", active: true)
    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::SURVEY_MANAGEMENT_BASE | Position::ALPHA, "Alpha Surveys")
    ensure_role(Role::ART_TRAINER_BASE | Position::ALPHA, "Alpha Trainer")

    # Survey manager: reaches the index and every report.
    @manager = person(:echelon_ranger)
    grant_role(@manager, Role::MENTOR)
    grant_role(@manager, Role::SURVEY_MANAGEMENT_BASE | Position::ALPHA)

    # Plain mentor: reaches the Mentoring section, but not the surveys.
    @plain_mentor = person(:retired_ranger)
    grant_role(@plain_mentor, Role::MENTOR)

    @outsider = person(:inactive_ranger)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- survey fixtures -------------------------------------------------------

  # An Alpha survey with an overall group (one rating, one comment question)
  # and, when asked for, a mentor group whose questions repeat per mentor.
  def build_survey(year: YEAR, mentor_group: false, type: Survey::ALPHA,
                   position: @alpha, title: nil)
    survey = Survey.create!(year:, type:, position_id: position.id, active: true,
                            title: title || "#{year} Alpha Survey",
                            prologue: "", epilogue: "")
    built = Built.new(survey:)

    overall = SurveyGroup.create!(survey_id: survey.id, type: SurveyGroup::TYPE_NORMAL,
                                  sort_index: 1, title: "Your Alpha Season", description: "",
                                  report_title: "")
    built.overall_rating = question(survey, overall, SurveyQuestion::TYPE_RATING,
                                    "Rate your Alpha season", 1)
    built.overall_comment = question(survey, overall, SurveyQuestion::TYPE_TEXT,
                                     "How was your Alpha season?", 2)

    if mentor_group
      group = SurveyGroup.create!(survey_id: survey.id, type: SurveyGroup::TYPE_TRAINER,
                                  sort_index: 2, title: "Your Mentors", description: "",
                                  report_title: "")
      built.mentor_group = group
      built.mentor_rating = question(survey, group, SurveyQuestion::TYPE_RATING,
                                     "Rate this mentor", 1, summarize_rating: true)
      built.mentor_comment = question(survey, group, SurveyQuestion::TYPE_TEXT,
                                      "Feedback for this mentor?", 2)
    end

    built
  end

  def question(survey, group, type, description, sort_index, summarize_rating: false)
    SurveyQuestion.create!(survey_id: survey.id, survey_group_id: group.id, type:,
                           description:, sort_index:, summarize_rating:)
  end

  # An Alpha survey's answers carry no slot -- nothing groups them by session.
  def answer(built, survey_question, respondent, response, mentor: nil, shared: true)
    SurveyAnswer.create!(survey_id: built.survey.id, survey_group_id: survey_question.survey_group_id,
                         survey_question_id: survey_question.id, person_id: respondent.id,
                         trainer_id: mentor&.id, slot_id: nil, response: response.to_s,
                         can_share_name: shared)
  end

  # --- index -----------------------------------------------------------------

  # Upstream's mentor/surveys takes no year: every season is on the one page.
  test "the index lists every year's Alpha survey, newest first" do
    old = build_survey(year: YEAR - 1, title: "#{YEAR - 1} Alpha Survey")
    current = build_survey(mentor_group: true)

    sign_in_as(@manager)
    get mentoring_surveys_path

    assert_response :success
    assert_select "h1", text: /Alpha Surveys/
    years = css_select("tbody th").map { |node| node.text.strip }
    assert_equal [YEAR.to_s, (YEAR - 1).to_s], years
    assert_select "a[href=?]", mentoring_survey_report_path(current.id, "main"),
                  text: "Alpha Overall Feedback"
    assert_select "a[href=?]", mentoring_survey_report_path(current.id, current.mentor_group.id),
                  text: "Alpha Feedback For Mentors"
    assert_select "a[href=?]", mentoring_survey_report_path(old.id, "main")
  end

  test "the index leaves a training survey off" do
    build_survey(type: Survey::TRAINING, position: @dirt, title: "#{YEAR} Training Survey")

    sign_in_as(@manager)
    get mentoring_surveys_path

    assert_response :success
    assert_no_match(/#{YEAR} Training Survey/, response.body)
    assert_match "No Alpha surveys have been created yet.", response.body
  end

  # Survey#has_responses finds answers through the slot they were given after,
  # and an Alpha survey's answers carry none -- Survey.find_for_query falls back
  # to asking the answers directly, which is what this is guarding.
  test "the index says which surveys have been answered" do
    answered = build_survey(mentor_group: true)
    build_survey(year: YEAR - 1, title: "#{YEAR - 1} Alpha Survey")
    answer(answered, answered.overall_comment, person(:alpha_ranger), "A long, hot week.")

    sign_in_as(@manager)
    get mentoring_surveys_path

    assert_response :success
    badges = css_select("tbody td:last-child").map { |node| node.text.strip }
    assert_equal ["Has responses", "None yet"], badges
  end

  # Holding Mentor reaches the section; reading a survey is a role on top of it.
  test "a mentor without survey management may not see the index" do
    sign_in_as(@plain_mentor)
    get mentoring_surveys_path

    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "someone outside the Mentoring section is turned away" do
    sign_in_as(@outsider)
    get mentoring_surveys_path

    assert_redirected_to me_root_path
  end

  # --- report ----------------------------------------------------------------

  test "the overall report shows the season's ratings and comments" do
    built = build_survey
    answer(built, built.overall_rating, person(:alpha_ranger), 6)
    answer(built, built.overall_rating, person(:active_ranger), 4)
    answer(built, built.overall_comment, person(:alpha_ranger), "My mentors kept me moving.")

    sign_in_as(@manager)
    get mentoring_survey_report_path(built.id, "main")

    assert_response :success
    assert_select "h1", text: /#{YEAR} Alpha Survey/
    assert_match "My mentors kept me moving.", response.body
    # Ratings 6 and 4: mean 5.0, variance 1.0, so the standard deviation is 1.0.
    assert_match "5.0", response.body
    assert_select "td", text: "1.0"
  end

  # The ranked table and the page per mentor are this port's addition --
  # upstream read an Alpha survey as one long report with no per-mentor view.
  test "mentor feedback ranks the mentors and links to each one" do
    built = build_survey(mentor_group: true)
    best = person(:active_ranger)
    worst = person(:auditor_ranger)
    answer(built, built.mentor_rating, person(:alpha_ranger), 7, mentor: best)
    answer(built, built.mentor_rating, person(:alpha_ranger), 3, mentor: worst)
    answer(built, built.mentor_comment, person(:alpha_ranger), "Answered every question.", mentor: best)

    sign_in_as(@manager)
    get mentoring_survey_report_path(built.id, built.mentor_group.id)

    assert_response :success
    ranked = css_select("#summary-0 th a").map(&:text).map(&:strip)
    assert_equal [best.callsign, worst.callsign], ranked
    # The survey rates mentors, so the page says Mentor and never Trainer. The
    # link carries this report's id so the mentor page can link back here.
    assert_select "a[href=?]",
                  mentoring_survey_mentor_path(built.id, best.id,
                                               report_id: built.mentor_group.id)
    assert_no_match(/Trainer/, response.body)
    # The comment itself lives on the mentor's own page, not the roster.
    assert_no_match(/Answered every question\./, response.body)
  end

  # SurveyBuilder used to collect these ratings and then drop them on the
  # floor -- the Alpha summarize branch built a SummarizedRating from the
  # always-empty responses list. They now report as a plain rating question.
  test "a summarized overall rating keeps its statistics" do
    built = build_survey
    group = SurveyGroup.find(built.overall_rating.survey_group_id)
    summarized = question(built.survey, group, SurveyQuestion::TYPE_RATING,
                          "Rate the whole season", 3, summarize_rating: true)
    answer(built, summarized, person(:alpha_ranger), 7)
    answer(built, summarized, person(:auditor_ranger), 3)

    sign_in_as(@manager)
    get mentoring_survey_report_path(built.id, "main")

    assert_response :success
    assert_match "Rate the whole season", response.body
    # Ratings 7 and 3: mean 5.0, variance 4.0, so the standard deviation is 2.0.
    assert_match "5.0", response.body
    assert_select "td", text: "2.0"
  end

  test "a training survey does not load through the Mentor interface" do
    other = build_survey(type: Survey::TRAINING, position: @dirt, title: "#{YEAR} Training Survey")

    sign_in_as(@manager)
    get mentoring_survey_report_path(other.id, "main")

    assert_redirected_to mentoring_surveys_path
    assert_match(/Survey not found/, flash[:error])
  end

  test "an unknown report id redirects instead of crashing" do
    built = build_survey

    sign_in_as(@manager)
    get mentoring_survey_report_path(built.id, "99999")

    assert_redirected_to mentoring_surveys_path
    assert_match(/report was not found/, flash[:error])
  end

  # SurveyPolicy#report denies its trainer fallback outright when the survey
  # sits at the Alpha position, so an Alpha trainer role does not open it.
  test "an Alpha trainer may not read the class's feedback" do
    built = build_survey
    grant_role(@plain_mentor, Role::ART_TRAINER_BASE | Position::ALPHA)

    sign_in_as(@plain_mentor)
    get mentoring_survey_report_path(built.id, "main")

    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "a report with no answers says so" do
    built = build_survey

    sign_in_as(@manager)
    get mentoring_survey_report_path(built.id, "main")

    assert_response :success
    assert_match "No one has answered this part of the survey yet.", response.body
  end

  # --- mentor page -----------------------------------------------------------

  test "the mentor page carries that mentor's comments and no one else's" do
    built = build_survey(mentor_group: true)
    mentor = person(:active_ranger)
    other = person(:auditor_ranger)
    answer(built, built.mentor_comment, person(:alpha_ranger), "Walked me through my first shift.",
           mentor:)
    answer(built, built.mentor_comment, person(:alpha_ranger), "Not this one's comment.", mentor: other)
    answer(built, built.mentor_rating, person(:alpha_ranger), 6, mentor:)

    sign_in_as(@manager)
    get mentoring_survey_mentor_path(built.id, mentor.id, report_id: built.mentor_group.id)

    assert_response :success
    assert_select "h1", text: /#{mentor.callsign}/
    assert_match "Walked me through my first shift.", response.body
    assert_no_match(/Not this one's comment\./, response.body)
    # "All mentors" returns to the report that linked here -- the roster lives
    # on the mentor-group report, not on "main".
    assert_select "a[href=?]", mentoring_survey_report_path(built.id, built.mentor_group.id)
  end

  # can_share_name is the Alpha's own choice, recorded per mentor.
  test "a comment is anonymous unless the Alpha shared their name" do
    built = build_survey(mentor_group: true)
    mentor = person(:active_ranger)
    answer(built, built.mentor_comment, person(:alpha_ranger), "Checked in on me every day.",
           mentor:, shared: true)
    answer(built, built.mentor_comment, person(:auditor_ranger), "Hard to find on the playa.",
           mentor:, shared: false)

    sign_in_as(@manager)
    get mentoring_survey_mentor_path(built.id, mentor.id)

    assert_response :success
    assert_match "Checked in on me every day.", response.body
    assert_match "Hard to find on the playa.", response.body
    assert_match person(:alpha_ranger).callsign, response.body
    assert_no_match(/#{person(:auditor_ranger).callsign}/, response.body)
    assert_match "Anonymous", response.body
  end

  # --- exports ---------------------------------------------------------------

  test "the comments export names the mentor column for what the survey rates" do
    built = build_survey(mentor_group: true)
    mentor = person(:active_ranger)
    answer(built, built.mentor_comment, person(:alpha_ranger), "Great teacher.", mentor:)

    sign_in_as(@manager)
    get mentoring_survey_report_path(built.id, built.mentor_group.id, format: :csv)

    assert_response :success
    assert_match "#{YEAR}-alpha-alpha-feedback-for-mentors-comments.csv",
                 response.headers["Content-Disposition"]

    # No Session/Location pair: an Alpha survey's answers carry no session, so
    # those two columns would be empty on every row of the file.
    lines = response.body.split("\n")
    assert_equal "Mentor,Respondent,Feedback for this mentor?", lines.first
    assert_equal "#{mentor.callsign},#{person(:alpha_ranger).callsign},Great teacher.", lines.second
  end

  test "the ratings export carries a real standard deviation" do
    built = build_survey(mentor_group: true)
    mentor = person(:active_ranger)
    answer(built, built.mentor_rating, person(:alpha_ranger), 7, mentor:)
    answer(built, built.mentor_rating, person(:auditor_ranger), 3, mentor:)

    sign_in_as(@manager)
    get mentoring_survey_report_path(built.id, built.mentor_group.id,
                                     kind: "ratings", format: :csv)

    assert_response :success
    assert_match "#{YEAR}-alpha-alpha-feedback-for-mentors-ratings.csv",
                 response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Question,Subject,Session Date,Avg Rating,Std Dev,Ratings,Distribution", lines.first
    # Ratings 7 and 3: mean 5.0, variance 4.0, so the standard deviation is 2.0.
    assert_equal "Rate this mentor,#{mentor.callsign},,5.0,2.0,2,3x1 7x1", lines.second
  end
end
