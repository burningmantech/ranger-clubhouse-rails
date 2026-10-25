# frozen_string_literal: true

require "test_helper"

# rubocop:disable Metrics/ClassLength
class Person::TrainingControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    # Pin the clock so Current.year == 2026, matching the online_course /
    # person_online_course fixtures.
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)         # has 2026 (open) + 2025 (completed) POC fixtures
    @admin = person(:auditor_ranger)         # ADMIN only -> view-only (guards admin: false)
    @trainer = person(:echelon_ranger)       # TRAINER -> manager
    @viewer = person(:ranger_with_custom_gender) # MENTOR -> view-only non-manager
    @past_year = Current.year - 1

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    ensure_role(Role::MENTOR, "Mentor")

    Current.person = @admin
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- View access tier (renders; requires the view stage) --------------------

  test "a trainer sees the online course management form" do
    setup_training_position
    grant_role(@trainer, Role::TRAINER)
    sign_in_as(@trainer)

    get person_training_path(@target, year: Current.year)

    assert_response :success
    assert_select "select[name=?]", "online_course_id"
  end

  test "an admin without trainer or tech ninja is view-only (no manage form)" do
    setup_training_position
    grant_role(@admin, Role::ADMIN)
    sign_in_as(@admin)

    get person_training_path(@target, year: Current.year)

    assert_response :success
    assert_select "select[name=?]", "online_course_id", count: 0
  end

  test "a non-manager viewer is view-only (no manage form)" do
    setup_training_position
    grant_role(@viewer, Role::MENTOR)
    sign_in_as(@viewer)

    get person_training_path(@target, year: Current.year)

    assert_response :success
    assert_select "select[name=?]", "online_course_id", count: 0
  end

  test "a user without any person-management role is redirected away" do
    # active_ranger holds none of the PersonConcern roles by default.
    sign_in_as(person(:active_ranger))

    get person_training_path(@target, year: Current.year)

    assert_redirected_to me_root_path
  end

  # --- update_online_course ---------------------------------------------------

  test "a trainer switches the assigned online course" do
    grant_role(@trainer, Role::TRAINER)
    sign_in_as(@trainer)
    new_course = online_course(:training_returning_2026)

    patch person_training_online_course_path(@target, year: Current.year),
          params: { online_course_id: new_course.id }

    assert_redirected_to person_training_path(@target, year: Current.year)
    poc = PersonOnlineCourse.find_for_person_year(@target.id, Current.year, Position::TRAINING)
    assert_equal new_course.id, poc.online_course_id
  end

  test "assigning a course from another position is rejected" do
    grant_role(@trainer, Role::TRAINER)
    sign_in_as(@trainer)
    wrong_course = online_course(:other_position_2026) # position_id 9
    original_id = person_online_course(:active_ranger_training_2026).online_course_id

    patch person_training_online_course_path(@target, year: Current.year),
          params: { online_course_id: wrong_course.id }

    assert_redirected_to person_training_path(@target, year: Current.year)
    assert_match(/does not match the training position/i, flash[:error])
    poc = PersonOnlineCourse.find_for_person_year(@target.id, Current.year, Position::TRAINING)
    assert_equal original_id, poc.online_course_id
  end

  test "an admin without trainer or tech ninja cannot switch the course" do
    grant_role(@admin, Role::ADMIN)
    sign_in_as(@admin)
    original_id = person_online_course(:active_ranger_training_2026).online_course_id

    patch person_training_online_course_path(@target, year: Current.year),
          params: { online_course_id: online_course(:training_returning_2026).id }

    assert_redirected_to person_training_path(@target, year: Current.year)
    assert_match(/Tech Ninja or Trainer/i, flash[:error])
    poc = PersonOnlineCourse.find_for_person_year(@target.id, Current.year, Position::TRAINING)
    assert_equal original_id, poc.online_course_id
  end

  test "a non-manager viewer cannot switch the course" do
    grant_role(@viewer, Role::MENTOR)
    sign_in_as(@viewer)

    patch person_training_online_course_path(@target, year: Current.year),
          params: { online_course_id: online_course(:training_returning_2026).id }

    assert_redirected_to person_training_path(@target, year: Current.year)
    assert_match(/Tech Ninja or Trainer/i, flash[:error])
  end

  # --- mark_online_course_completed -------------------------------------------

  test "a trainer force-marks the online course completed" do
    grant_role(@trainer, Role::TRAINER)
    sign_in_as(@trainer)
    assert_nil person_online_course(:active_ranger_training_2026).completed_at

    post person_training_mark_completed_path(@target, year: Current.year)

    assert_redirected_to person_training_path(@target, year: Current.year)
    poc = PersonOnlineCourse.find_for_person_year(@target.id, Current.year, Position::TRAINING)
    assert_not_nil poc.completed_at
  end

  test "force-marking an already-completed course is rejected" do
    grant_role(@trainer, Role::TRAINER)
    person_online_course(:active_ranger_training_2026).update!(completed_at: Current.time)
    sign_in_as(@trainer)

    post person_training_mark_completed_path(@target, year: Current.year)

    assert_redirected_to person_training_path(@target, year: Current.year)
    assert_match(/already completed/i, flash[:error])
  end

  test "force-mark completed is denied outside the current year" do
    grant_role(@trainer, Role::TRAINER)
    sign_in_as(@trainer)

    post person_training_mark_completed_path(@target, year: @past_year)

    # The current-year YearGate halts before the action runs; the year-specific
    # flash (not the "already completed" one) proves the gate fired.
    assert_redirected_to person_training_path(@target, year: @past_year)
    assert_match(/only be performed for the current year/i, flash[:error])
  end

  # --- Moodle-API actions -----------------------------------------------------

  test "sync reports a not-set-up flash when the person has no Moodle Account" do
    grant_role(@trainer, Role::TRAINER)
    sign_in_as(@trainer)
    assert @target.lms_id.blank?

    post person_training_sync_path(@target, year: Current.year)

    assert_redirected_to person_training_path(@target, year: Current.year)
    assert_match(/not set up or linked/i, flash[:error])
  end

  test "reset password reports a not-set-up flash when the person has no Moodle Account" do
    grant_role(@trainer, Role::TRAINER)
    sign_in_as(@trainer)
    assert @target.lms_id.blank?

    post person_training_reset_password_path(@target, year: Current.year)

    assert_redirected_to person_training_path(@target, year: Current.year)
    assert_match(/not set up or linked/i, flash[:error])
  end

  test "a Moodle outage surfaces an error flash" do
    @target.update!(lms_id: 8_675_309)
    grant_role(@trainer, Role::TRAINER)
    sign_in_as(@trainer)

    stub_moodle_request_web_service(Moodle::DownForMaintenanceError) do
      post person_training_sync_path(@target, year: Current.year)
    end

    assert_redirected_to person_training_path(@target, year: Current.year)
    assert_match(/maintenance/i, flash[:error])
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id: id)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id: role_id)
    RoleManager.purge_person(person.id.to_s)
  end

  # PersonEventInfo falls back to Position.find(Position::TRAINING) when the person
  # has no training positions, so the row must exist for the index to render.
  def setup_training_position
    Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end
  end

  # Drive the controller's Moodle error handling by making the single web-service
  # seam raise. Moodle#initialize is neutralized too so the test does not depend on
  # live Moodle settings. (Minitest 6 dropped minitest/mock, so a save/restore
  # monkey patch is used.)
  def stub_moodle_request_web_service(error_class)
    original_initialize = Moodle.instance_method(:initialize)
    original_request = Moodle.instance_method(:request_web_service)
    Moodle.send(:define_method, :initialize) { |*_args| }
    Moodle.send(:define_method, :request_web_service) { |*_args| raise error_class }
    yield
  ensure
    Moodle.send(:define_method, :initialize, original_initialize)
    Moodle.send(:define_method, :request_web_service, original_request)
  end
end
# rubocop:enable Metrics/ClassLength
