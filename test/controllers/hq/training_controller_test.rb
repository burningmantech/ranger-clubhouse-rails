# frozen_string_literal: true

require "test_helper"

# The in-shell HQ training page. The status rendering itself is the shared
# common/training partials, exercised by the person-training suite, so the
# assertions here concentrate on what is genuinely new:
#
#   * the widened audience — Shift Management alone reaches the page, where the
#     sidebar link-out it replaces demanded the person-page roles;
#   * read-only — none of the person page's management affordances render, and
#     no write route exists to reach;
#   * current year only — a ?year= param cannot move the page off Current.year.
class Hq::TrainingControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @viewer = person(:active_ranger)
    @subject = person(:ranger_with_custom_gender)

    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@viewer, Role::SHIFT_MANAGEMENT)

    # PersonEventInfo's training lookup falls back to
    # Position.find(Position::TRAINING) — the fixtures do not pin that id.
    Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end

    sign_in_as(@viewer)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- Access gates ----------------------------------------------------------

  test "redirects away when the HQ Window Interface setting is off" do
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get hq_training_path(@subject)

    assert_redirected_to person_path(@subject)
  end

  test "requires the admin or shift management permission" do
    sign_in_as(@subject) # holds no roles at all

    get hq_training_path(@viewer)

    assert_redirected_to me_root_path
  end

  test "a shift management only operator reaches the page" do
    assert_equal [Role::SHIFT_MANAGEMENT], @viewer.person_role.pluck(:role_id),
                 "the viewer must hold Shift Management and nothing else for this test to mean anything"

    get hq_training_path(@subject)

    assert_response :success
    assert_select "#hq-training-header", text: /#{Current.year} Training & ARTs/
  end

  # --- Read-only -------------------------------------------------------------

  test "none of the person page's management affordances render" do
    get hq_training_path(@subject)

    assert_response :success
    assert_select "select[name=?]", "online_course_id", count: 0
    assert_no_match(/Moodle/, @response.body)
    # The shell chrome has forms of its own, so scope this to the page's own path.
    assert_select "form[action^=?]", hq_training_path(@subject), count: 0
  end

  test "no write routes exist under the hq training path" do
    routes = Rails.application.routes

    assert routes.recognize_path("/hq/#{@subject.id}/training", method: :get)
    [:post, :patch, :put, :delete].each do |method|
      assert_raises(ActionController::RoutingError, "#{method.upcase} must not be routable") do
        routes.recognize_path("/hq/#{@subject.id}/training", method:)
      end
    end
  end

  # --- Current year only -----------------------------------------------------

  test "a year param cannot move the page off the current year" do
    get hq_training_path(@subject, year: Current.year - 1)

    assert_response :success
    assert_select "#hq-training-header", text: /#{Current.year} Training & ARTs/
  end

  # --- Content ---------------------------------------------------------------

  test "the online course completion state renders for the current year" do
    get hq_training_path(@subject)

    assert_response :success
    assert_match(/#{Current.year} completion:/, @response.body)
    assert_match(/Not Completed/, @response.body)
  end
end
