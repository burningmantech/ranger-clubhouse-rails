# frozen_string_literal: true

require "test_helper"
require "ostruct"

# online_course.yml's fixtures deliberately point at position_id 13 with no
# matching position fixture (see the comment in that file) -- every test here
# creates the Training position row itself so course.position.title and the
# belongs_to presence validation both have something real to resolve.
class Admin::OnlineCoursesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  # A Moodle stand-in whose three lookup methods return canned values -- the
  # seam Moodle.new is stubbed to return, so no test ever touches the network.
  FakeMoodle = Struct.new(:enrollment, :courses, :course_info) do
    def retrieve_course_enrollment_with_completion(_course_id) = enrollment
    def retrieve_available_courses = courses
    def retrieve_course_info(_course_id) = course_info
  end

  # A Moodle stand-in that raises on every call, for the error-handling paths.
  RaisingMoodle = Struct.new(:error) do
    def retrieve_course_enrollment_with_completion(_course_id) = raise(error)
    def retrieve_available_courses = raise(error)
    def retrieve_course_info(_course_id) = raise(error)
  end

  setup do
    Rails.cache.clear
    OnlineCourse.delete_all

    @training = Position.create!(id: 13, title: "Training", type: Position::TYPE_TRAINING, active: true)

    @admin = person(:auditor_ranger)
    @outsider = person(:active_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    @all_course = OnlineCourse.create!(position_id: @training.id, year: 2026, course_for: "all",
                                        course_id: "38", name: "2026 Black Rock Ranger Training", active: true)
    @returning_course = OnlineCourse.create!(position_id: @training.id, year: 2026, course_for: "returning",
                                              course_id: "39", name: "", active: true)
    @inactive_course = OnlineCourse.create!(position_id: @training.id, year: 2026, course_for: "new",
                                             course_id: "40", name: "", active: false)
  end

  teardown do
    Rails.cache.clear
  end

  # minitest/mock's Object#stub isn't available in this project's minitest
  # version (it was split into a separate gem) -- this is the same
  # replace-then-restore trick without the dependency.
  def stub_moodle(fake)
    original = Moodle.method(:new)
    Moodle.define_singleton_method(:new) { fake }
    yield
  ensure
    Moodle.define_singleton_method(:new, original)
  end

  # ---------------------------------------------------------------- access

  test "a non-admin is bounced from the index" do
    sign_in_as(@outsider)

    get admin_online_courses_path

    assert_response :redirect
  end

  # ---------------------------------------------------------------- index

  test "admin sees each course with its position, audience, and id" do
    sign_in_as(@admin)

    get admin_online_courses_path(year: 2026)

    assert_response :success
    assert_select "h1", text: /Online Courses/
    assert_select "tbody tr", count: 3
    assert_select "th", text: "Training", count: 3
    assert_select "td", text: "38"
  end

  test "a course whose name has not been synced shows a dash, not a blank cell" do
    sign_in_as(@admin)

    get admin_online_courses_path(year: 2026)

    assert_response :success
    assert_select "td", text: "—"
  end

  test "everyone-plus-specific audiences on one position are flagged as overlapping" do
    sign_in_as(@admin)

    get admin_online_courses_path(year: 2026)

    assert_response :success
    assert_select "body", text: /Audience overlap/
  end

  test "an inactive course is badged Inactive" do
    sign_in_as(@admin)

    get admin_online_courses_path(year: 2026)

    assert_response :success
    assert_select "body", text: /Inactive/
  end

  test "the year selector narrows the list to that year" do
    OnlineCourse.create!(position_id: @training.id, year: 2025, course_for: "all", course_id: "31")

    sign_in_as(@admin)

    get admin_online_courses_path(year: 2025)

    assert_response :success
    assert_select "tbody tr", count: 1
  end

  test "no courses for a year shows the empty state, not an empty table" do
    sign_in_as(@admin)

    get admin_online_courses_path(year: 2023)

    assert_response :success
    assert_select "body", text: /No online courses have been defined for 2023/
  end

  # ------------------------------------------------------------ create/new

  test "creating a course with a free position, year, and audience succeeds" do
    sign_in_as(@admin)

    assert_difference "OnlineCourse.count", 1 do
      post admin_online_courses_path, params: {
        online_course: { position_id: @training.id, year: 2027, course_for: "all", course_id: "50", active: "1" }
      }
    end

    assert_redirected_to admin_online_courses_path(year: 2027)
  end

  test "creating a course without a course id fails validation" do
    sign_in_as(@admin)

    assert_no_difference "OnlineCourse.count" do
      post admin_online_courses_path, params: {
        online_course: { position_id: @training.id, year: 2027, course_for: "all", course_id: "" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "creating a second course for the same position, year, and audience fails with a plain message" do
    sign_in_as(@admin)

    assert_no_difference "OnlineCourse.count" do
      post admin_online_courses_path, params: {
        online_course: { position_id: @training.id, year: 2026, course_for: "all", course_id: "99" }
      }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /already has a course for this year and audience/
  end

  test "the new form is pre-filled from a Moodle catalog course id and name" do
    sign_in_as(@admin)

    get new_admin_online_course_path(year: 2027, course_id: "77", course_name: "2027 Draft Course")

    assert_response :success
    assert_select "input[value=?]", "77"
  end

  # --------------------------------------------------------------- update

  test "updating a course changes its audience but never its year" do
    # The "new" slot is free once the inactive fixture course is out of the way.
    @inactive_course.destroy!

    sign_in_as(@admin)

    patch admin_online_course_path(@returning_course), params: {
      online_course: { position_id: @training.id, course_for: "new", course_id: "39", year: 1999 }
    }

    assert_redirected_to admin_online_courses_path(year: 2026)
    @returning_course.reload
    assert_equal "new", @returning_course.course_for
    assert_equal 2026, @returning_course.year
  end

  test "changing an audience to one already taken fails instead of raising" do
    sign_in_as(@admin)

    patch admin_online_course_path(@returning_course), params: {
      online_course: { position_id: @training.id, course_for: "all", course_id: "39" }
    }

    assert_response :unprocessable_entity
    assert_equal "returning", @returning_course.reload.course_for
  end

  # -------------------------------------------------------------- destroy

  test "deleting a course removes it and returns to its year" do
    sign_in_as(@admin)

    assert_difference "OnlineCourse.count", -1 do
      delete admin_online_course_path(@inactive_course)
    end

    assert_redirected_to admin_online_courses_path(year: 2026)
  end

  # -------------------------------------------------------------- set_name

  test "syncing the name saves the LMS course's current name" do
    fake = FakeMoodle.new(nil, nil, OpenStruct.new(fullname: "2026 Ranger Online Course (Synced)"))

    sign_in_as(@admin)

    stub_moodle(fake) do
      post set_name_admin_online_course_path(@all_course)
    end

    assert_redirected_to edit_admin_online_course_path(@all_course)
    assert_equal "2026 Ranger Online Course (Synced)", @all_course.reload.name
  end

  test "syncing a course id the LMS does not recognize leaves the name unchanged" do
    fake = FakeMoodle.new(nil, nil, nil)

    sign_in_as(@admin)

    stub_moodle(fake) do
      post set_name_admin_online_course_path(@all_course)
    end

    assert_redirected_to edit_admin_online_course_path(@all_course)
    assert_equal "2026 Black Rock Ranger Training", @all_course.reload.name
  end

  test "syncing the name during LMS maintenance shows a plain error and leaves the name unchanged" do
    fake = RaisingMoodle.new(Moodle::DownForMaintenanceError.new)

    sign_in_as(@admin)

    stub_moodle(fake) do
      post set_name_admin_online_course_path(@all_course)
    end

    assert_redirected_to edit_admin_online_course_path(@all_course)
    assert_equal "2026 Black Rock Ranger Training", @all_course.reload.name
  end

  # ----------------------------------------------------------- enrollment

  test "the enrollment page names the position and year, and loads the roster lazily" do
    sign_in_as(@admin)

    get enrollment_admin_online_course_path(@all_course)

    assert_response :success
    assert_select "h1", text: /Moodle Enrollment/
    assert_select "turbo-frame#online-course-enrollment[src=?]",
                  enrollment_roster_admin_online_course_path(@all_course)
    # Without this the callsign links inside the roster resolve into the frame
    # and never open the person page.
    assert_select "turbo-frame#online-course-enrollment[target=?]", "_top"
  end

  test "a completion time is shown in the same clock the LMS reported" do
    student = OpenStruct.new(id: 4211, idnumber: nil, username: "nov", email: "nov@example.org",
                              completed_at: "2026-11-20 09:15:00 -0700", person: nil)
    fake = FakeMoodle.new([student], nil, nil)

    sign_in_as(@admin)

    stub_moodle(fake) do
      get enrollment_roster_admin_online_course_path(@all_course)
    end

    assert_response :success
    assert_select "body", text: /09:15/
  end

  test "the enrollment roster shows a matched person, an unmatched account, and a non-student" do
    matched = OpenStruct.new(id: 4211, idnumber: @admin.id.to_s, username: "admin", email: "admin@example.org",
                              completed_at: "2026-07-12 14:02:00 -0700",
                              person: OpenStruct.new(id: @admin.id, callsign: @admin.callsign, status: @admin.status))
    unmatched = OpenStruct.new(id: 4400, idnumber: nil, username: "jsmith88", email: "jsmith88@example.org",
                                completed_at: nil, person: nil)
    teacher = OpenStruct.new(id: 4109, idnumber: nil, username: "compass", email: "compass@example.org",
                              completed_at: nil, is_teacher: true, person: nil)
    fake = FakeMoodle.new([matched, unmatched, teacher], nil, nil)

    sign_in_as(@admin)

    stub_moodle(fake) do
      get enrollment_roster_admin_online_course_path(@all_course)
    end

    assert_response :success
    assert_select "body", text: /#{@admin.callsign}/
    assert_select "body", text: /\* unknown \*/
    assert_select "body", text: /Not enrolled as student/
    assert_select "body", text: /not yet/
  end

  test "an unreachable LMS shows a plain error instead of a broken enrollment page" do
    fake = RaisingMoodle.new(Moodle::ConnectFailureError.new("no route to host"))

    sign_in_as(@admin)

    stub_moodle(fake) do
      get enrollment_roster_admin_online_course_path(@all_course)
    end

    assert_response :success
    assert_select "body", text: /Could not reach the LMS/
  end

  test "the Groundhog Day Server never calls out to the real LMS" do
    sign_in_as(@admin)

    ENV["RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"] = "2026-08-01 12:00:00"
    begin
      get enrollment_roster_admin_online_course_path(@all_course)
    ensure
      ENV.delete("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME")
    end

    assert_response :success
    assert_select "body", text: /Groundhog Day Server/
  end

  # ------------------------------------------------------------- catalog

  test "the catalog page loads its listing lazily" do
    sign_in_as(@admin)

    get moodle_catalog_admin_online_courses_path(year: 2026)

    assert_response :success
    assert_select "h1", text: /Moodle Course Catalog/
    assert_select "turbo-frame#online-course-catalog[src=?]",
                  moodle_catalog_courses_admin_online_courses_path(year: 2026)
    # Without this the Create Course buttons resolve into the frame and the
    # page's only action does nothing.
    assert_select "turbo-frame#online-course-catalog[target=?]", "_top"
  end

  test "the catalog shows a course's linked definitions and an unlinked course as none" do
    linked = OpenStruct.new(id: 38, fullname: "2026 Black Rock Ranger Training")
    unlinked = OpenStruct.new(id: 77, fullname: "2027 Draft Course")
    fake = FakeMoodle.new(nil, [linked, unlinked], nil)

    sign_in_as(@admin)

    stub_moodle(fake) do
      get moodle_catalog_courses_admin_online_courses_path(year: 2026)
    end

    assert_response :success
    assert_select "body", text: /2026 · Training \(Everyone\)/
    assert_select "body", text: /— none —/
    assert_select "a[href=?]", new_admin_online_course_path(year: 2026, course_id: 77, course_name: "2027 Draft Course")
  end
end
