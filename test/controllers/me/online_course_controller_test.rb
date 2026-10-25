# frozen_string_literal: true

require "test_helper"
require "ostruct"

class Me::OnlineCourseControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers

  SITE_URL = "https://lms.example.org/login/index.php"
  ART_QUESTION = "Where is my Advanced Ranger Training course?"
  IN_PERSON_QUESTION = "Is the course all I need?"

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Setting.create!(name: Setting::ONLINE_COURSE_SITE_URL, value: SITE_URL)
    # person_online_course.yml already enrolls active_ranger in 2026.
    PersonOnlineCourse.delete_all
    @ranger = person(:active_ranger)
    sign_in_as(@ranger)
  end

  test "the page says how to sign in before sending anyone to the course" do
    get me_online_course_path

    assert_response :success
    assert_select "h1", text: /Online Course/
    assert_select "dd", text: /Login Using The Clubhouse/
    assert_select "dt", text: IN_PERSON_QUESTION
    assert_select "dt", text: ART_QUESTION, count: 0
    assert_select "form[action='#{me_online_course_path}'][method=post][data-turbo=false]" do
      assert_select "input[type=submit][value='Go to Online Course']"
    end
  end

  test "from an ART's link the page says where the ART course is instead" do
    get me_online_course_path(art: 1)

    assert_response :success
    assert_select "dt", text: ART_QUESTION
    assert_select "dt", text: IN_PERSON_QUESTION, count: 0
    assert_select "form[action='#{me_online_course_path(art: 1)}']"
  end

  test "a new account is created, enrolled in this year's course, and sent to the course site" do
    calls = stub_moodle(Moodle::WS_CREATE_USERS => [OpenStruct.new(id: 501)]) { post me_online_course_path }

    assert_redirected_to "#{SITE_URL}?username=testranger"
    assert_equal [Moodle::WS_SEARCH_USERS, Moodle::WS_CREATE_USERS, Moodle::WS_ENROLL_USERS], calls
    assert_equal "501", @ranger.reload.lms_id
    assert_equal online_course(:training_all_2026).id, enrollment.online_course_id
    assert_not_nil enrollment.enrolled_at
  end

  test "an existing account is brought up to date before a new enrollment, and left alone once enrolled" do
    @ranger.update_columns(lms_id: "77", lms_username: "oldname")

    calls = stub_moodle { post me_online_course_path }

    assert_redirected_to "#{SITE_URL}?username=testranger"
    assert_equal [Moodle::WS_UPDATE_USERS, Moodle::WS_ENROLL_USERS], calls
    assert_equal "testranger", @ranger.reload.lms_username
    assert ActionLog.exists?(event: "lms-sync-user", person_id: @ranger.id)

    calls = stub_moodle { post me_online_course_path }

    assert_redirected_to "#{SITE_URL}?username=testranger"
    assert_empty calls
  end

  # With no course for everyone, an active Ranger with two or more years takes
  # the returning course and anyone else the new one. An inactive course is
  # never chosen.
  test "without a course for everyone, years as a Ranger pick the course" do
    online_course(:training_all_2026).update_columns(active: false)
    online_course(:training_new_2026_inactive).update_columns(active: true)
    @ranger.update_columns(lms_id: "77")

    stub_moodle { post me_online_course_path }
    assert_equal online_course(:training_returning_2026).id, enrollment.online_course_id

    @ranger.update_columns(years_as_ranger: [2024])
    stub_moodle { post me_online_course_path }
    assert_equal online_course(:training_new_2026_inactive).id, enrollment.online_course_id
  end

  test "no course this year is explained, and nothing is sent to Moodle" do
    OnlineCourse.update_all(active: false)

    calls = stub_moodle { post me_online_course_path }

    assert_redirected_to me_online_course_path
    assert_match "isn't set up yet", flash[:error]
    assert_empty calls
  end

  test "Moodle down for maintenance sends the person back to try later, from an ART too" do
    stub_moodle(Moodle::WS_SEARCH_USERS => Moodle::DownForMaintenanceError.new) { post me_online_course_path(art: 1) }

    assert_redirected_to me_online_course_path(art: 1)
    assert_match "down for maintenance", flash[:error]
    assert_nil enrollment
  end

  test "the Groundhog Day Server never sets up an account" do
    ENV["RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"] = "2026-04-16 12:00:00"
    begin
      calls = stub_moodle { post me_online_course_path }
    ensure
      ENV.delete("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME")
    end

    assert_redirected_to me_root_path
    assert_match "Groundhog Day Server", flash[:error]
    assert_empty calls
  end

  private

  def enrollment
    PersonOnlineCourse.find_for_person_year(@ranger.id, 2026, Position::TRAINING)
  end

  # Moodle's single web-service seam, answered by service name from +responses+
  # (an exception is raised). initialize is neutralized so no Moodle settings
  # are read and nothing leaves the test. Returns the services called, in order.
  def stub_moodle(responses = {})
    calls = []
    original_initialize = Moodle.instance_method(:initialize)
    original_request = Moodle.instance_method(:request_web_service)
    Moodle.define_method(:initialize) { nil }
    Moodle.define_method(:request_web_service) do |_method, service, _data = {}|
      calls << service
      response = responses[service]
      response.is_a?(Exception) ? raise(response) : response
    end
    yield
    calls
  ensure
    Moodle.define_method(:initialize, original_initialize)
    Moodle.define_method(:request_web_service, original_request)
  end
end
