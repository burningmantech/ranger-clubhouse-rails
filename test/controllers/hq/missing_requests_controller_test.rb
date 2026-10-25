# frozen_string_literal: true

require "test_helper"

# The HQ twin of Me::MissingRequestsController. The CRUD behaviour is shared
# through MissingRequestsConcern and covered by the /me suite; these tests pin
# the HQ specifics: always-on corrections, the subject/creator attribution
# split, and that every path stays inside /hq.
class Hq::MissingRequestsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @viewer = person(:active_ranger)
    @subject = person(:ranger_with_custom_gender)
    @position = positions(:khaki_supervisor)

    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@viewer, Role::SHIFT_MANAGEMENT)

    Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end

    PersonPosition.find_or_create_by!(person: @subject, position: @position)

    sign_in_as(@viewer)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "index and new render with corrections setting off" do
    assert_nil Setting.find_by(name: Setting::TIMESHEET_CORRECTION_ENABLE),
               "fixture guard: the corrections setting must be absent (off) for this test to mean anything"

    get hq_missing_requests_path(@subject)
    assert_response :success

    get new_hq_missing_request_path(@subject)
    assert_response :success
  end

  test "the me missing request pages still honour the corrections setting" do
    sign_in_as(@subject)

    get me_missing_requests_path

    assert_redirected_to me_timesheet_dashboard_path
    assert_equal "Timesheet corrections are not enabled.", flash[:error]
  end

  test "create records the person as owner and the operator as creator" do
    post hq_missing_requests_path(@subject), params: {
      timesheet_missing: {
        position_id: @position.id,
        on_duty: "2026-08-28T10:00",
        off_duty: "2026-08-28T16:00",
        partner: "Slats",
        additional_notes: "Shift never made it into the timesheet."
      }
    }

    assert_redirected_to hq_missing_requests_path(@subject)
    request = TimesheetMissing.order(:id).last
    assert_equal @subject.id, request.person_id
    assert_equal @viewer.id, request.create_person_id
    assert_equal TimesheetMissing::STATUS_PENDING, request.review_status
  end

  test "a request belonging to someone else is not editable" do
    other = TimesheetMissing.new(person_id: @viewer.id, create_person_id: @viewer.id,
                                 position_id: @position.id,
                                 on_duty: Time.zone.local(2026, 8, 28, 10, 0, 0),
                                 off_duty: Time.zone.local(2026, 8, 28, 16, 0, 0),
                                 partner: "Slats",
                                 review_status: TimesheetMissing::STATUS_PENDING)
    other.save!(validate: false)

    get edit_hq_missing_request_path(@subject, other)

    assert_redirected_to hq_missing_requests_path(@subject)
    assert_equal "The missing timesheet request was not found.", flash[:error]
  end
end
