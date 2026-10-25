# frozen_string_literal: true

require "test_helper"

# Training > Surveys: the survey-management gate (tighter than the interface's
# own view gate), the three audience sections, the report and per-trainer
# pages, the anonymity rule, and the two exports.
class Training::SurveysControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ArtMentoringTestHelper # also TrainingSlotTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  # A built survey and the questions a test needs to answer.
  Built = Struct.new(:survey, :venue_rating, :venue_comment,
                     :trainer_group, :trainer_rating, :trainer_comment, keyword_init: true) do
    def id = survey.id
  end

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)
    # The mentor and mentee sections come from the cadre's ART mentoring flags.
    setup_art_mentoring
    @green_dot, @gd_mentor = @training, @mentor_position

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::SURVEY_MANAGEMENT_TRAINING, "Survey Management")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")
    ensure_role(Role::SURVEY_MANAGEMENT_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Surveys")

    # Survey manager: sees the index and every report.
    @manager = person(:echelon_ranger)
    grant_role(@manager, Role::TRAINER)
    grant_role(@manager, Role::SURVEY_MANAGEMENT_TRAINING)

    # Plain trainer: reaches the interface and a training survey's reports,
    # but neither the survey index nor trainer-on-trainer feedback.
    @plain_trainer = person(:retired_ranger)
    grant_role(@plain_trainer, Role::TRAINER)

    @outsider = person(:inactive_ranger)

    @session = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0),
                                  description: "Bay Area, CA")
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- survey fixtures -------------------------------------------------------

  # A survey with a venue group (one rating, one comment question) and, when
  # asked for, a trainer group whose questions repeat per trainer.
  def build_survey(type: Survey::TRAINING, position: @dirt, mentoring_position: nil,
                   trainer_group: false, title: nil)
    survey = Survey.create!(year: YEAR, type:, position_id: position.id, active: true,
                            mentoring_position_id: mentoring_position&.id,
                            title: title || "#{YEAR} #{position.title} Survey",
                            prologue: "", epilogue: "")
    built = Built.new(survey:)

    venue = SurveyGroup.create!(survey_id: survey.id, type: SurveyGroup::TYPE_NORMAL,
                                sort_index: 1, title: "The Venue", description: "", report_title: "")
    built.venue_rating = question(survey, venue, SurveyQuestion::TYPE_RATING, "Rate the venue", 1)
    built.venue_comment = question(survey, venue, SurveyQuestion::TYPE_TEXT, "What about the venue?", 2)

    if trainer_group
      group = SurveyGroup.create!(survey_id: survey.id, type: SurveyGroup::TYPE_TRAINER,
                                  sort_index: 2, title: "Your Trainers", description: "",
                                  report_title: "")
      built.trainer_group = group
      built.trainer_rating = question(survey, group, SurveyQuestion::TYPE_RATING,
                                      "Rate this trainer", 1, summarize_rating: true)
      built.trainer_comment = question(survey, group, SurveyQuestion::TYPE_TEXT,
                                       "Feedback for this trainer?", 2)
    end

    built
  end

  def question(survey, group, type, description, sort_index, summarize_rating: false)
    SurveyQuestion.create!(survey_id: survey.id, survey_group_id: group.id, type:,
                           description:, sort_index:, summarize_rating:)
  end

  def answer(built, survey_question, respondent, response, trainer: nil, slot: @session, shared: true)
    SurveyAnswer.create!(survey_id: built.survey.id, survey_group_id: survey_question.survey_group_id,
                         survey_question_id: survey_question.id, person_id: respondent.id,
                         trainer_id: trainer&.id, slot_id: slot&.id, response: response.to_s,
                         can_share_name: shared)
  end

  # --- index -----------------------------------------------------------------

  test "the index lists a year's surveys with their reports" do
    built = build_survey(trainer_group: true)

    sign_in_as(@manager)
    get training_surveys_path("in-person")

    assert_response :success
    assert_select "h1", text: /Training Surveys/
    assert_select "th", text: /Trainees on their training/
    assert_select "a[href=?]",
                  training_survey_report_path("in-person", built.id, "main", year: YEAR),
                  text: "Venue Feedback"
    assert_select "a[href=?]",
                  training_survey_report_path("in-person", built.id, built.trainer_group.id,
                                              year: YEAR),
                  text: "Trainee-on-Trainer Feedback"
  end

  # Upstream split these across three sidebar links and a ?position_id= query
  # parameter; one survey-management role covers all three.
  test "an ART shows its training, mentor and mentee surveys as sections" do
    grant_role(@manager, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
    grant_role(@manager, Role::SURVEY_MANAGEMENT_BASE | Position::GREEN_DOT_TRAINING)
    # A survey sits at the position of whoever answers it, which is how the
    # sections are split: mentors rating their mentees is a Mentor survey.
    build_survey(type: Survey::MENTOR_FOR_MENTEES, position: @gd_mentor,
                 mentoring_position: Position.find(Position::GREEN_DOT_MENTEE),
                 title: "#{YEAR} GD Mentor-on-Mentee Survey")

    sign_in_as(@manager)
    get training_surveys_path("green-dot")

    assert_response :success
    titles = css_select("[role=heading]").map { |node| node.text.sub(node.css(".badge").text, "").strip }
    assert_includes titles, "Training Surveys"
    assert_includes titles, "Mentor Surveys"
    assert_includes titles, "Mentee Surveys"
    assert_match "#{YEAR} GD Mentor-on-Mentee Survey", response.body
    assert_match "No Green Dot Mentee surveys were created for #{YEAR}.", response.body
  end

  # A trainer-on-trainer survey is reported whole, one trainer at a time, so a
  # separate group of its own would otherwise be offered as a link that
  # renders the very same page.
  test "a trainer-on-trainer survey offers exactly one report" do
    built = build_survey(type: Survey::TRAINER, trainer_group: true,
                         title: "#{YEAR} Trainer Survey")

    sign_in_as(@manager)
    get training_surveys_path("in-person")

    assert_response :success
    assert_select "a[href=?]",
                  training_survey_report_path("in-person", built.id, "main", year: YEAR),
                  text: "Trainer-On-Trainer Feedback"
    assert_select "a[href=?]",
                  training_survey_report_path("in-person", built.id, built.trainer_group.id,
                                              year: YEAR),
                  count: 0
  end

  test "a trainer without survey management may not see the index" do
    sign_in_as(@plain_trainer)
    get training_surveys_path("in-person")

    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "someone outside the training interface is turned away" do
    sign_in_as(@outsider)
    get training_surveys_path("in-person")

    assert_redirected_to me_root_path
  end

  # --- report ----------------------------------------------------------------

  test "the venue report shows ratings and comments by session" do
    built = build_survey
    answer(built, built.venue_rating, person(:active_ranger), 6)
    answer(built, built.venue_rating, person(:alpha_ranger), 4)
    answer(built, built.venue_comment, person(:active_ranger), "The room was too cold.")

    sign_in_as(@manager)
    get training_survey_report_path("in-person", built.id, "main")

    assert_response :success
    assert_select "h1", text: /#{YEAR} Training Survey/
    assert_match "The room was too cold.", response.body
    assert_match "Bay Area, CA", response.body
    # Ratings 6 and 4: mean 5.0, variance 1.0, standard deviation 1.0.
    assert_match "5.0", response.body
    assert_select "td", text: "1.0"
  end

  # The ranked table is the option-B replacement for upstream's stack of
  # collapsed per-trainer accordions.
  test "trainer feedback ranks the trainers and links to each one" do
    built = build_survey(trainer_group: true)
    best = person(:active_ranger)
    worst = person(:alpha_ranger)
    answer(built, built.trainer_rating, person(:auditor_ranger), 7, trainer: best)
    answer(built, built.trainer_rating, person(:auditor_ranger), 3, trainer: worst)
    answer(built, built.trainer_comment, person(:auditor_ranger), "Clear and patient.", trainer: best)

    sign_in_as(@manager)
    get training_survey_report_path("in-person", built.id, built.trainer_group.id)

    assert_response :success
    # Ranked by average, not alphabetically -- AlphaNewbie would sort first.
    ranked = css_select("#summary-0 th a").map(&:text).map(&:strip)
    assert_equal [best.callsign, worst.callsign], ranked
    # The link carries this report's id so the trainer page can link back here.
    assert_select "a[href=?]",
                  training_survey_trainer_path("in-person", built.id, best.id,
                                               year: YEAR, report_id: built.trainer_group.id)
    # The comment itself lives on the trainer's own page, not the roster.
    assert_no_match(/Clear and patient\./, response.body)
  end

  test "a plain trainer may read training feedback but not trainer-on-trainer" do
    training_survey = build_survey(trainer_group: true)
    trainer_survey = build_survey(type: Survey::TRAINER, title: "#{YEAR} Trainer Survey")
    answer(trainer_survey, trainer_survey.venue_comment, person(:active_ranger),
           "Ran the room well.", trainer: person(:alpha_ranger))

    sign_in_as(@plain_trainer)

    get training_survey_report_path("in-person", training_survey.id, "main")
    assert_response :success

    get training_survey_report_path("in-person", trainer_survey.id, "main")
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "a survey belonging to another training does not load under this slug" do
    other = build_survey(position: @green_dot, title: "#{YEAR} Green Dot Survey")

    sign_in_as(@manager)
    get training_survey_report_path("in-person", other.id, "main")

    assert_redirected_to training_surveys_path("in-person", year: YEAR)
    assert_match(/Survey not found/, flash[:error])
  end

  test "an unknown report id redirects instead of crashing" do
    built = build_survey

    sign_in_as(@manager)
    get training_survey_report_path("in-person", built.id, "99999")

    assert_redirected_to training_surveys_path("in-person", year: YEAR)
    assert_match(/report was not found/, flash[:error])
  end

  test "a report with no answers says so" do
    built = build_survey

    sign_in_as(@manager)
    get training_survey_report_path("in-person", built.id, "main")

    assert_response :success
    assert_match "No one has answered this part of the survey yet.", response.body
  end

  # --- anonymity -------------------------------------------------------------

  # can_share_name is the respondent's own choice, recorded per trainer when
  # the survey is taken. SurveyBuilder ignored it before this page existed.
  test "a comment is anonymous unless the respondent shared their name" do
    built = build_survey(trainer_group: true)
    trainer = person(:active_ranger)
    answer(built, built.trainer_comment, person(:auditor_ranger), "Kept us moving.",
           trainer:, shared: true)
    answer(built, built.trainer_comment, person(:alpha_ranger), "Talked over people.",
           trainer:, shared: false)

    sign_in_as(@manager)
    get training_survey_trainer_path("in-person", built.id, trainer.id)

    assert_response :success
    assert_match "Kept us moving.", response.body
    assert_match "Talked over people.", response.body
    assert_match person(:auditor_ranger).callsign, response.body
    assert_no_match(/#{person(:alpha_ranger).callsign}/, response.body)
    assert_match "Anonymous", response.body
  end

  # --- trainer page ----------------------------------------------------------

  test "the trainer page carries that trainer's comments and no one else's" do
    built = build_survey(trainer_group: true)
    trainer = person(:active_ranger)
    other = person(:alpha_ranger)
    answer(built, built.trainer_comment, person(:auditor_ranger), "Explained the radio well.",
           trainer:)
    answer(built, built.trainer_comment, person(:auditor_ranger), "Not this one's comment.",
           trainer: other)
    answer(built, built.trainer_rating, person(:auditor_ranger), 6, trainer:)

    sign_in_as(@manager)
    get training_survey_trainer_path("in-person", built.id, trainer.id)

    assert_response :success
    assert_select "h1", text: /#{trainer.callsign}/
    assert_match "Explained the radio well.", response.body
    assert_no_match(/Not this one's comment\./, response.body)
  end

  test "a trainer with no feedback gets an empty state, not an error" do
    built = build_survey(trainer_group: true)

    sign_in_as(@manager)
    get training_survey_trainer_path("in-person", built.id, person(:active_ranger).id)

    assert_response :success
    assert_match "has given #{person(:active_ranger).callsign} feedback", response.body
  end

  # --- exports ---------------------------------------------------------------

  test "the comments export carries one column per question" do
    built = build_survey(trainer_group: true)
    trainer = person(:active_ranger)
    answer(built, built.trainer_comment, person(:auditor_ranger), "Great pacing.", trainer:)

    sign_in_as(@manager)
    get training_survey_report_path("in-person", built.id, built.trainer_group.id, format: :csv)

    assert_response :success
    assert_match "#{YEAR}-in-person-trainee-on-trainer-feedback-comments.csv",
                 response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Session,Location,Trainer,Respondent,Feedback for this trainer?", lines.first
    assert_equal "#{YEAR}-06-01 09:00,\"Bay Area, CA\",#{trainer.callsign}," \
                 "#{person(:auditor_ranger).callsign},Great pacing.",
                 lines.second
  end

  # A manual-review (summary) group's answers carry no session, but its file
  # keeps the stable Session,Location header -- only an Alpha survey, whose
  # answers never have a session, drops the pair. Downstream sheets key on
  # the column positions.
  test "a summary report's export keeps the Session and Location columns" do
    built = build_survey
    group = SurveyGroup.create!(survey_id: built.survey.id, type: SurveyGroup::TYPE_SUMMARY,
                                sort_index: 3, title: "Manual Review", description: "",
                                report_title: "Manual Review")
    prompt = question(built.survey, group, SurveyQuestion::TYPE_TEXT, "Anything else?", 1)
    answer(built, prompt, person(:active_ranger), "All good.", slot: nil)

    sign_in_as(@manager)
    get training_survey_report_path("in-person", built.id, group.id, format: :csv)

    assert_response :success
    lines = response.body.split("\n")
    assert_equal "Session,Location,Respondent,Anything else?", lines.first
    assert_equal ",,#{person(:active_ranger).callsign},All good.", lines.second
  end

  # Upstream keyed its export rows by the respondent's id, which an anonymous
  # answer does not have, so every anonymous answer for a session collapsed
  # onto one row and all but the last were dropped.
  test "the comments export keeps every anonymous answer" do
    built = build_survey(trainer_group: true)
    trainer = person(:active_ranger)
    answer(built, built.trainer_comment, person(:auditor_ranger), "First anonymous note.",
           trainer:, shared: false)
    answer(built, built.trainer_comment, person(:alpha_ranger), "Second anonymous note.",
           trainer:, shared: false)

    sign_in_as(@manager)
    get training_survey_report_path("in-person", built.id, built.trainer_group.id, format: :csv)

    assert_response :success
    assert_match "First anonymous note.", response.body
    assert_match "Second anonymous note.", response.body
    assert_equal 3, response.body.split("\n").size
  end

  # SurveyBuilder computes variance; upstream printed it as "Std. Dev." on the
  # page and exported (mean / 7) / 100 in the CSV column of the same name.
  test "the ratings export carries a real standard deviation" do
    built = build_survey(trainer_group: true)
    trainer = person(:active_ranger)
    answer(built, built.trainer_rating, person(:auditor_ranger), 7, trainer:)
    answer(built, built.trainer_rating, person(:alpha_ranger), 3, trainer:)

    sign_in_as(@manager)
    get training_survey_report_path("in-person", built.id, built.trainer_group.id,
                                    kind: "ratings", format: :csv)

    assert_response :success
    assert_match "#{YEAR}-in-person-trainee-on-trainer-feedback-ratings.csv",
                 response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Question,Subject,Session Date,Avg Rating,Std Dev,Ratings,Distribution", lines.first
    # Ratings 7 and 3: mean 5.0, variance 4.0, so the standard deviation is 2.0.
    assert_equal "Rate this trainer,#{trainer.callsign},,5.0,2.0,2,3x1 7x1", lines.second
  end
end
