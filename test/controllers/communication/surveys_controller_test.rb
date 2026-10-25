# frozen_string_literal: true

require "test_helper"

# Communication > Survey Management: the two gates (the section, and each
# survey's own cadre), the year-scoped list, the survey form, and duplication.
class Communication::SurveysControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include SurveyTestHelper
  include DomIdTestHelper
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
  # Reaching the section
  # ==========================================================================

  test "someone with no survey role may not reach the page" do
    sign_in_as(@outsider)

    get communication_surveys_path

    assert_redirected_to me_root_path
    assert_equal "Admin or a Survey Management role is required to manage surveys.", flash[:error]
  end

  # A permission composed on another base must not open this page: the gate
  # tests the base, and every ART permission is base | position.
  test "a permission composed on another base does not open the page" do
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")
    grant_role(@outsider, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)

    sign_in_as(@outsider)
    get communication_surveys_path

    assert_redirected_to me_root_path
  end

  test "a survey role composed for one training opens the page" do
    sign_in_as(@art_manager)

    get communication_surveys_path

    assert_response :success
  end

  # Admin is the one branch of has_role_for_position? that answers before it
  # looks at a position at all, so every cadre's survey has to be reachable.
  test "an admin manages every cadre's surveys" do
    mine = create_survey(position: @dirt, title: "#{YEAR} Ranger Training Feedback")
    theirs = create_survey(position: @green_dot, title: "#{YEAR} Green Dot Feedback")

    sign_in_as(@admin)
    get communication_surveys_path

    assert_response :success
    assert_match mine.title, response.body
    assert_match theirs.title, response.body

    get communication_survey_path(theirs)
    assert_response :success
  end

  test "the flat Survey Management role opens the page" do
    sign_in_as(@dirt_manager)

    get communication_surveys_path

    assert_response :success
  end

  # ==========================================================================
  # The list
  # ==========================================================================

  test "the list holds only the surveys the person manages" do
    mine = create_survey(position: @dirt, title: "#{YEAR} Ranger Training Feedback")
    theirs = create_survey(position: @green_dot, title: "#{YEAR} Green Dot Feedback")

    sign_in_as(@dirt_manager)
    get communication_surveys_path

    assert_response :success
    assert_match mine.title, response.body
    assert_no_match(/#{Regexp.escape(theirs.title)}/, response.body)
  end

  test "the list is scoped to the year in the selector" do
    this_year = create_survey(position: @dirt, title: "#{YEAR} Feedback")
    last_year = create_survey(position: @dirt, year: YEAR - 1, title: "#{YEAR - 1} Feedback")

    sign_in_as(@dirt_manager)
    get communication_surveys_path(year: YEAR - 1)

    assert_response :success
    assert_match last_year.title, response.body
    assert_no_match(/#{Regexp.escape(this_year.title)}/, response.body)
  end

  test "the list says which surveys are switched off and which have answers" do
    create_survey(position: @dirt, active: false, title: "#{YEAR} Draft Feedback")

    sign_in_as(@dirt_manager)
    get communication_surveys_path

    assert_response :success
    assert_select "td", text: /Inactive/
    assert_select "td", text: /None yet/
  end

  test "a survey with answers says so, on the list and on its own page" do
    survey = create_survey(position: @dirt, title: "#{YEAR} Answered Feedback")
    question = create_survey_question(survey, create_survey_group(survey))
    create_survey_answer(question, person: @outsider)

    sign_in_as(@dirt_manager)
    get communication_surveys_path

    assert_response :success
    assert_select "td", text: /Has responses/
    assert_select "td", text: /Active/

    # The survey's own page is not loaded through the list's finder, so it has
    # to answer this for itself rather than reporting "none yet".
    get communication_survey_path(survey)

    assert_response :success
    assert_match "Has responses", response.body
    assert_no_match(/None yet/, response.body)
  end

  test "the list shows the position a mentoring survey asks about" do
    create_survey(position: @gd_mentee, type: Survey::MENTEES_FOR_MENTOR,
                  mentoring_position: @gd_mentor, title: "#{YEAR} Green Dot Mentee Feedback")

    sign_in_as(@art_manager)
    get communication_surveys_path

    assert_response :success
    assert_match "about Green Dot Mentor", response.body
  end

  # Four real survey permissions name a position the Clubhouse does not map to
  # surveys. The page opens for them, and has to say why it is empty.
  test "a survey role that covers no position is told so, and offered no New Survey" do
    # Tow Truck Training is not named in Position::SURVEY_MANAGEMENT_POSITIONS,
    # so this permission covers no position at all -- four real permissions
    # are in exactly this state.
    assert_not Position::SURVEY_MANAGEMENT_POSITIONS.key?(Position::TOW_TRUCK_TRAINING)
    Position.create!(id: Position::TOW_TRUCK_TRAINING, title: "Tow Truck Training",
                     type: Position::TYPE_TRAINING, active: true)
    stranded = person(:auditor_ranger)
    ensure_role(Role::SURVEY_MANAGEMENT_BASE | Position::TOW_TRUCK_TRAINING, "Tow Truck Survey Mgmt")
    grant_role(stranded, Role::SURVEY_MANAGEMENT_BASE | Position::TOW_TRUCK_TRAINING)

    sign_in_as(stranded)
    get communication_surveys_path

    assert_response :success
    assert_match "Does Not Cover Any Position Yet", response.body
    assert_select "a[href=?]", new_communication_survey_path(year: YEAR), count: 0
  end

  test "a group id sent as a list is ignored rather than crashing" do
    survey = create_survey(position: @dirt)
    create_survey_group(survey, title: "The Venue")

    sign_in_as(@dirt_manager)
    get communication_survey_path(survey, group: ["1"])

    assert_response :success
    assert_select "[data-controller=scroll-to-element]", count: 0
  end

  test "a year with no surveys says so" do
    sign_in_as(@dirt_manager)

    get communication_surveys_path

    assert_response :success
    assert_match "No surveys were created for #{YEAR}", response.body
  end

  # ==========================================================================
  # One survey's page
  # ==========================================================================

  test "the survey page lists its groups and questions in order" do
    survey = create_survey(position: @dirt)
    second = create_survey_group(survey, title: "Parting Thoughts", sort_index: 7)
    first = create_survey_group(survey, title: "The Venue", sort_index: 1)
    create_survey_question(survey, first, description: "Rate the venue",
                                          type: SurveyQuestion::TYPE_RATING, is_required: true)

    sign_in_as(@dirt_manager)
    get communication_survey_path(survey)

    assert_response :success
    assert_select "#group-#{first.id}"
    assert_select "#group-#{second.id}"
    assert_operator response.body.index("The Venue"), :<, response.body.index("Parting Thoughts")
    assert_match "Rate the venue", response.body
    assert_select "td", text: /Required/
  end

  # The page repeats a section and a table per group, under a layout that
  # morphs on refresh -- a repeated id would make Turbo replace the wrong one.
  test "the survey page gives every element it repeats its own id" do
    survey = create_survey(position: @dirt)
    2.times { |i| create_survey_group(survey, title: "Group #{i}", sort_index: i + 1) }
    create_survey_question(survey, survey.survey_groups.first, description: "How was it?")

    sign_in_as(@dirt_manager)
    get communication_survey_path(survey)

    assert_response :success
    assert_unique_dom_ids
  end

  test "the survey page says whether the survey is active" do
    survey = create_survey(position: @dirt, active: false)

    sign_in_as(@dirt_manager)
    get communication_survey_path(survey)

    assert_response :success
    assert_match "This survey is not active.", response.body
  end

  test "a survey with no groups says what to do next" do
    survey = create_survey(position: @dirt)

    sign_in_as(@dirt_manager)
    get communication_survey_path(survey)

    assert_response :success
    assert_match "This survey has no groups yet.", response.body
  end

  test "the survey page links to where its answers are read" do
    survey = create_survey(position: @dirt)

    sign_in_as(@admin)
    get communication_survey_path(survey)

    assert_response :success
    assert_select "a[href=?]", training_surveys_path("in-person", year: YEAR)
  end

  # The page that shows the answers is gated on the training interface's own
  # roles, which a survey permission does not imply -- offering the link to
  # someone it will turn away is worse than not offering it.
  test "the link to the answers is not offered to someone who cannot follow it" do
    survey = create_survey(position: @dirt)

    sign_in_as(@dirt_manager)
    get communication_survey_path(survey)

    assert_response :success
    assert_select "a[href=?]", training_surveys_path("in-person", year: YEAR), count: 0
  end

  test "the page scrolls to the group an edit came back from" do
    survey = create_survey(position: @dirt)
    create_survey_group(survey, title: "The Venue", sort_index: 1)
    second = create_survey_group(survey, title: "Parting Thoughts", sort_index: 2)

    sign_in_as(@dirt_manager)
    get communication_survey_path(survey, group: second.id)

    assert_response :success
    assert_select "[data-controller=scroll-to-element][data-scroll-to-element-id-value=?]",
                  "group-#{second.id}"
  end

  test "a group id from another survey scrolls to nothing" do
    survey = create_survey(position: @dirt)
    create_survey_group(survey, title: "The Venue")
    elsewhere = create_survey_group(create_survey(position: @dirt, type: Survey::TRAINER, title: "Another"))

    sign_in_as(@dirt_manager)
    get communication_survey_path(survey, group: elsewhere.id)

    assert_response :success
    assert_select "[data-controller=scroll-to-element]", count: 0
  end

  test "another cadre's survey may not be opened" do
    survey = create_survey(position: @green_dot)

    sign_in_as(@dirt_manager)
    get communication_survey_path(survey)

    assert_redirected_to me_root_path
    assert_equal "You are not authorized to manage that survey.", flash[:error]
  end

  # params merges the query string, so a parameter named after the one the
  # nested routes use must not be able to stand in for the id in the path --
  # a delete would take a survey the reader never saw.
  test "a survey id in the query string does not stand in for the one in the path" do
    named = create_survey(position: @dirt, title: "#{YEAR} Named In The Path")
    other = create_survey(position: @dirt, type: Survey::TRAINER, title: "#{YEAR} Somewhere Else")

    sign_in_as(@dirt_manager)
    get communication_survey_path(named, survey_id: other.id)

    assert_response :success
    assert_match named.title, response.body
    assert_no_match(/#{Regexp.escape(other.title)}/, response.body)

    assert_difference "Survey.count", -1 do
      delete communication_survey_path(named, survey_id: other.id)
    end

    assert_nil Survey.find_by(id: named.id)
    assert Survey.exists?(other.id)
  end

  test "a survey id that does not exist lands back on the list" do
    sign_in_as(@dirt_manager)

    get communication_survey_path(999_999)

    assert_redirected_to communication_surveys_path
    assert_equal "Survey not found.", flash[:error]
  end

  # ==========================================================================
  # Creating
  # ==========================================================================

  test "the new survey form offers only the kinds and positions the person manages" do
    sign_in_as(@dirt_manager)

    get new_communication_survey_path(year: YEAR)

    assert_response :success
    # Scoped to the Position select: the About select offers every mentor and
    # mentee position to everyone, because it names who is being rated.
    assert_select "select[name=?] option[value=?]", "survey[position_id]", @dirt.id.to_s
    assert_select "select[name=?] option[value=?]", "survey[position_id]", @green_dot.id.to_s, count: 0
    assert_select "select[name=?] option[value=?]", "survey[type]", Survey::TRAINING
    assert_select "select[name=?] option[value=?]", "survey[type]", Survey::ALPHA, count: 0
  end

  test "an ART survey manager is offered their mentor and mentee positions" do
    sign_in_as(@art_manager)

    get new_communication_survey_path(year: YEAR)

    assert_response :success
    assert_select "select[name=?] option[value=?]", "survey[position_id]", @gd_mentor.id.to_s
    assert_select "select[name=?] option[value=?]", "survey[position_id]", @gd_mentee.id.to_s
    assert_select "select[name=?] option[value=?]", "survey[type]", Survey::MENTEES_FOR_MENTOR
  end

  test "create makes a survey in the year being viewed" do
    sign_in_as(@dirt_manager)

    assert_difference "Survey.count", 1 do
      post communication_surveys_path(year: YEAR - 1), params: {
        survey: { type: Survey::TRAINING, position_id: @dirt.id, title: "#{YEAR - 1} Feedback",
                  prologue: "<p>Hello</p>", epilogue: "<p>Thanks</p>", active: "1" }
      }
    end

    survey = Survey.order(:id).last
    assert_redirected_to communication_survey_path(survey)
    assert_equal YEAR - 1, survey.year
    assert_equal "#{YEAR - 1} Feedback", survey.title
    # A survey is switched on from its own page, once it has questions to ask,
    # so a create never switches one on however the form is posted.
    assert_not survey.active
  end

  test "create records the new survey in the action log" do
    sign_in_as(@dirt_manager)

    assert_difference "ActionLog.where(event: 'survey-create').count", 1 do
      post communication_surveys_path(year: YEAR), params: {
        survey: { type: Survey::TRAINING, position_id: @dirt.id, title: "#{YEAR} Feedback",
                  prologue: "p", epilogue: "e" }
      }
    end
  end

  test "create refuses a position the person does not manage" do
    sign_in_as(@dirt_manager)

    assert_no_difference "Survey.count" do
      post communication_surveys_path(year: YEAR), params: {
        survey: { type: Survey::TRAINING, position_id: @green_dot.id, title: "#{YEAR} Feedback",
                  prologue: "p", epilogue: "e" }
      }
    end

    assert_response :unprocessable_entity
    assert_match "Position must be one you manage surveys for", response.body
  end

  test "create refuses a position of the wrong kind for the survey" do
    sign_in_as(@art_manager)

    assert_no_difference "Survey.count" do
      post communication_surveys_path(year: YEAR), params: {
        survey: { type: Survey::TRAINING, position_id: @gd_mentor.id, title: "#{YEAR} Feedback",
                  prologue: "p", epilogue: "e" }
      }
    end

    assert_response :unprocessable_entity
    assert_match "Position must be a training position for this kind of survey", response.body
  end

  test "create refuses a mentoring survey with nothing to ask about" do
    sign_in_as(@art_manager)

    assert_no_difference "Survey.count" do
      post communication_surveys_path(year: YEAR), params: {
        survey: { type: Survey::MENTEES_FOR_MENTOR, position_id: @gd_mentee.id,
                  title: "#{YEAR} Feedback", prologue: "p", epilogue: "e" }
      }
    end

    assert_response :unprocessable_entity
    assert_match "About must name the position this survey asks about", response.body
  end

  test "create refuses a survey with no title, and says which field is missing" do
    sign_in_as(@dirt_manager)

    assert_no_difference "Survey.count" do
      post communication_surveys_path(year: YEAR), params: {
        survey: { type: Survey::TRAINING, position_id: @dirt.id, title: "",
                  prologue: "p", epilogue: "e" }
      }
    end

    assert_response :unprocessable_entity
    # The error summary prints a message with no field name in front of it, so
    # a bare "can't be blank" would leave the reader hunting.
    assert_select "#form-error-summary", text: /Title can't be blank/
  end

  # ==========================================================================
  # Editing and deleting
  # ==========================================================================

  test "the edit form opens with the survey's details in it" do
    survey = create_survey(position: @dirt, title: "#{YEAR} Ranger Training Feedback")

    sign_in_as(@dirt_manager)
    get edit_communication_survey_path(survey)

    assert_response :success
    assert_select "input[name=?][value=?]", "survey[title]", survey.title
    assert_select "a[href=?]", communication_survey_path(survey)
  end

  test "update changes the survey and can switch it on" do
    survey = create_survey(position: @dirt, active: false)
    create_survey_question(survey, create_survey_group(survey), description: "How was it?")

    sign_in_as(@dirt_manager)
    patch communication_survey_path(survey), params: {
      survey: { type: survey.type, position_id: @dirt.id, title: "Renamed",
                prologue: survey.prologue, epilogue: survey.epilogue, active: "1" }
    }

    assert_redirected_to communication_survey_path(survey)
    survey.reload
    assert_equal "Renamed", survey.title
    assert survey.active
  end

  # An active survey with no questions is offered on the dashboard, answering
  # it writes nothing, and the task never clears.
  test "a survey with no questions may not be switched on" do
    survey = create_survey(position: @dirt, active: false)

    sign_in_as(@dirt_manager)
    patch communication_survey_path(survey), params: {
      survey: { type: survey.type, position_id: @dirt.id, title: survey.title,
                prologue: survey.prologue, epilogue: survey.epilogue, active: "1" }
    }

    assert_response :unprocessable_entity
    assert_match "Add a question before switching this survey on", response.body
    assert_not survey.reload.active
  end

  # One survey of a kind, per position, per year: the page people answer takes
  # the first it finds, so a second one collects the answers meant for it.
  test "a second survey of the same kind for the same position and year is refused" do
    create_survey(position: @dirt, title: "#{YEAR} Ranger Training Feedback")

    sign_in_as(@dirt_manager)

    assert_no_difference "Survey.count" do
      post communication_surveys_path(year: YEAR), params: {
        survey: { type: Survey::TRAINING, position_id: @dirt.id, title: "#{YEAR} Second Feedback",
                  prologue: "p", epilogue: "e" }
      }
    end

    assert_response :unprocessable_entity
    assert_match "There is already a #{YEAR} survey of this kind", response.body
  end

  test "update drops the position a survey no longer asks about" do
    survey = create_survey(position: @gd_mentee, type: Survey::MENTEES_FOR_MENTOR,
                           mentoring_position: @gd_mentor)

    sign_in_as(@art_manager)
    patch communication_survey_path(survey), params: {
      survey: { type: Survey::TRAINING, position_id: @green_dot.id, title: survey.title,
                mentoring_position_id: @gd_mentor.id,
                prologue: survey.prologue, epilogue: survey.epilogue }
    }

    assert_redirected_to communication_survey_path(survey)
    assert_nil survey.reload.mentoring_position_id
  end

  test "update refuses to move a survey to a position the person does not manage" do
    survey = create_survey(position: @dirt)

    sign_in_as(@dirt_manager)
    patch communication_survey_path(survey), params: {
      survey: { type: survey.type, position_id: @green_dot.id, title: survey.title,
                prologue: survey.prologue, epilogue: survey.epilogue }
    }

    assert_response :unprocessable_entity
    assert_equal @dirt.id, survey.reload.position_id
  end

  test "delete takes the groups, questions and answers with it" do
    survey = create_survey(position: @dirt)
    group = create_survey_group(survey)
    question = create_survey_question(survey, group)
    create_survey_answer(question, person: @outsider)

    sign_in_as(@dirt_manager)

    assert_difference ["Survey.count", "SurveyGroup.count", "SurveyQuestion.count",
                       "SurveyAnswer.count"], -1 do
      delete communication_survey_path(survey)
    end

    assert_redirected_to communication_surveys_path(year: YEAR)
    assert_match "\" deleted.", flash[:success]
  end

  test "another cadre's survey may not be deleted" do
    survey = create_survey(position: @green_dot)

    sign_in_as(@dirt_manager)

    assert_no_difference "Survey.count" do
      delete communication_survey_path(survey)
    end

    assert_redirected_to me_root_path
  end

  # ==========================================================================
  # Duplicating
  # ==========================================================================

  test "duplicate copies the survey into this year, switched off" do
    survey = create_survey(position: @dirt, year: YEAR - 1, active: true,
                           title: "#{YEAR - 1} Ranger Training Feedback")
    group = create_survey_group(survey, title: "The Venue")
    create_survey_question(survey, group, description: "Rate the venue")

    sign_in_as(@dirt_manager)

    assert_difference "Survey.count", 1 do
      post duplicate_communication_survey_path(survey)
    end

    copy = Survey.order(:id).last
    assert_redirected_to communication_survey_path(copy)
    assert_equal YEAR, copy.year
    assert_not copy.active
    assert_equal "#{YEAR} Ranger Training Feedback", copy.title
    assert_equal ["The Venue"], copy.survey_groups.map(&:title)
    assert_equal ["Rate the venue"], SurveyQuestion.where(survey_id: copy.id).map(&:description)
    assert_not_equal survey.survey_groups.first.id, copy.survey_groups.first.id
    assert_equal copy.survey_groups.first.id,
                 SurveyQuestion.where(survey_id: copy.id).first.survey_group_id
  end

  test "duplicate leaves the original alone" do
    survey = create_survey(position: @dirt, year: YEAR - 1, active: true)
    create_survey_group(survey)

    sign_in_as(@dirt_manager)
    post duplicate_communication_survey_path(survey)

    survey.reload
    assert survey.active
    assert_equal YEAR - 1, survey.year
    assert_equal 1, survey.survey_groups.count
  end

  test "a survey that cannot be copied says so and copies nothing" do
    survey = create_survey(position: @dirt, year: YEAR - 1)
    group = create_survey_group(survey, title: "The Venue")
    # A group saved before its report needed a name. The copy is a new record,
    # so it is held to the rule and the whole copy is abandoned.
    group.update_columns(type: SurveyGroup::TYPE_SUMMARY, report_title: "")

    sign_in_as(@dirt_manager)

    assert_no_difference ["Survey.count", "SurveyGroup.count"] do
      post duplicate_communication_survey_path(survey)
    end

    assert_redirected_to communication_survey_path(survey)
    assert_match "could not be copied", flash[:error]
  end

  # A second survey of the same kind at the same position in the same year is
  # a twin: the page people answer takes the first one it finds, so the copy
  # can collect the answers meant for the live survey.
  test "a survey is not copied on top of one that already covers the same year" do
    survey = create_survey(position: @dirt, title: "#{YEAR} Ranger Training Feedback")

    sign_in_as(@dirt_manager)

    assert_no_difference "Survey.count" do
      post duplicate_communication_survey_path(survey)
    end

    assert_redirected_to communication_survey_path(survey)
    assert_match "There is already a #{YEAR} survey of this kind", flash[:error]
  end

  test "a copy is made when the year holds a survey of another kind" do
    create_survey(position: @dirt, type: Survey::TRAINER, title: "#{YEAR} Trainer Feedback")
    survey = create_survey(position: @dirt, year: YEAR - 1, title: "#{YEAR - 1} Training Feedback")

    sign_in_as(@dirt_manager)

    assert_difference "Survey.count", 1 do
      post duplicate_communication_survey_path(survey)
    end
  end

  test "another cadre's survey may not be duplicated" do
    survey = create_survey(position: @green_dot, year: YEAR - 1)

    sign_in_as(@dirt_manager)

    assert_no_difference "Survey.count" do
      post duplicate_communication_survey_path(survey)
    end

    assert_redirected_to me_root_path
  end
end
