# frozen_string_literal: true

require "test_helper"

class Me::ScheduleControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TrainingSlotTestHelper

  test "index uses the custom message for excepted statuses" do
    sign_in_as(person(:bonked_ranger))

    get me_schedule_url

    assert_redirected_to me_root_path
    assert_equal "You are not permitted to sign up for trainings or shifts at this time.", flash[:error]
  end

  # A removal the store refuses is an error, not a success.
  test "destroy reports a failed removal as an error" do
    person = person(:active_ranger)
    sign_in_as(person)
    slot = create_slot(positions(:council_manager), begins: 1.year.from_now)
    sign_up(person, slot)
    failed = Scheduling::Signup::SignupResult.from(Scheduling::Verdict::Failed.new(status: Scheduling::STATUS_DB_FAILURE))
    original = Scheduling::Signup.method(:remove)
    Scheduling::Signup.define_singleton_method(:remove) { |*_args| failed }

    begin
      delete me_schedule_destroy_url(slot)
    ensure
      Scheduling::Signup.define_singleton_method(:remove, original)
    end

    assert_redirected_to me_schedule_path(year: Current.year)
    assert_equal "The shift could not be removed. Reload the page and try again.", flash[:error]
    assert_nil flash[:success]
  end

  # An applicant without the Online Course still gets the page: the year's
  # Training sessions by month as a preview, and none of the sign-up links.
  test "index previews the training sessions to an applicant without the online course" do
    training = Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end
    applicant = person(:alpha_ranger)
    PersonPosition.find_or_create_by!(person: applicant, position: training)
    upcoming = create_slot(training, begins: 40.days.from_now, description: "Reno - Full Day")
    past = create_slot(training, begins: 40.days.ago, description: "Oakland - Full Day")
    sign_in_as(applicant)

    get me_schedule_url

    assert_response :success
    # An applicant's missing course is a requirement, so it is listed under
    # "Action Required" rather than given the Ranger-only "Online Course Required" heading.
    assert_select "[role=alert] li", text: /Online Course/
    assert_select ".card-standard h3", text: /#{upcoming.begins.strftime("%B")}\s+1 session/
    assert_select "li", text: "Reno - Full Day"
    assert_select ".card-standard h3", text: /#{past.begins.strftime("%B")}\s+1 session/
    assert_select "li", text: "Oakland - Full Day"
    assert_select "a[href=?]", me_available_sign_up_path(year: Current.year), count: 0
    assert_select "a[href=?]", me_schedule_qualifications_path(year: Current.year), count: 0
    assert_select "a[href=?]", me_schedule_signup_summary_path(year: Current.year), count: 0
  end

  test "index hides the schedule behind the blocker warning until it is opened" do
    ranger = person(:active_ranger)
    ranger.update!(callsign_approved: false)
    sign_in_as(ranger)

    get me_schedule_url

    assert_response :success
    assert_select "#schedule-gate:not([open]) > summary", text: /View Schedule/
    assert_select "#schedule-gate:not([open]) a[href=?]", me_available_sign_up_path(year: Current.year)

    # A past year has no blockers, so the gate renders already open.
    get me_schedule_url(year: Current.year - 1)

    assert_response :success
    assert_select "#schedule-gate[open]"
  end
end
