# frozen_string_literal: true

require "test_helper"

# rubocop:disable Metrics/ClassLength
class Person::VehiclesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @vehicle_manager = person(:echelon_ranger)
    @viewer = person(:ranger_with_custom_gender)
    @past_year = Current.year - 1

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VEHICLE_MANAGEMENT, "Vehicle Management")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vehicle_manager, Role::EVENT_MANAGEMENT)
    grant_role(@vehicle_manager, Role::VEHICLE_MANAGEMENT)
    grant_role(@viewer, Role::MENTOR)

    Current.person = @admin
    PersonEvent.where(person_id: @target.id).delete_all
    @target.update!(vehicle_blacklisted: false)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "admin current-year page shows all edit forms" do
    sign_in_as(@admin)

    get person_vehicles_path(@target, year: Current.year)

    assert_response :success
    assert_select "body", text: /Driving Privileges/i
    assert_select "input[name='person_event[org_vehicle_insurance]'][type='checkbox']", count: 1
    assert_select "input[name='person_event[may_request_stickers]'][type='checkbox']", count: 1
    motorpool = "input[name='person_event[signed_motorpool_agreement]'][type='checkbox']"
    assert_select motorpool, count: 1
    assert_select "input[name='person[vehicle_blacklisted]'][type='checkbox']", count: 1
    assert_select "input[type='submit'][value='Save MVR Flags']", count: 1
    assert_select "input[type='submit'][value='Save PVR Flags']", count: 1
    assert_select "input[type='submit'][value='Save Agreements']", count: 1
    assert_select "input[type='submit'][value='Save Blacklist']", count: 1
  end

  # Clubhouse 2 offered these flags and agreements to Admin alone; Vehicle Management
  # (with Event Management here) only reads them.
  test "vehicle manager sees no edit forms" do
    sign_in_as(@vehicle_manager)

    get person_vehicles_path(@target, year: Current.year)

    assert_response :success
    assert_select "input[name='person_event[org_vehicle_insurance]'][type='checkbox']", count: 0
    assert_select "input[name='person_event[may_request_stickers]'][type='checkbox']", count: 0
    assert_select "input[name='person_event[signed_motorpool_agreement]'][type='checkbox']", count: 0
    assert_select "input[name='person[vehicle_blacklisted]'][type='checkbox']", count: 0
  end

  test "vehicle manager is refused every flag and agreement update and changes nothing" do
    sign_in_as(@vehicle_manager)

    {
      update_mvr_flags_person_vehicles_path(@target, year: Current.year) => { org_vehicle_insurance: "1" },
      update_pvr_flags_person_vehicles_path(@target, year: Current.year) => { may_request_stickers: "1" },
      update_agreements_person_vehicles_path(@target, year: Current.year) => { signed_motorpool_agreement: "1" }
    }.each do |path, fields|
      assert_no_difference -> { PersonEvent.where(person_id: @target.id).count }, path do
        patch path, params: { person_event: fields }
      end
      assert_redirected_to person_vehicles_path(@target, year: Current.year)
      assert_equal "Admin permission required to update vehicle records.", flash[:error]
    end
  end

  test "non-editor viewer sees badges instead of edit forms" do
    sign_in_as(@viewer)

    get person_vehicles_path(@target, year: Current.year)

    assert_response :success
    assert_select "input[name='person_event[org_vehicle_insurance]'][type='checkbox']", count: 0
    assert_select "input[name='person_event[may_request_stickers]'][type='checkbox']", count: 0
    assert_select "input[name='person[vehicle_blacklisted]'][type='checkbox']", count: 0
    assert_select "body", text: /not authorized/
  end

  test "past-year page hides edit forms even for admin" do
    sign_in_as(@admin)

    get person_vehicles_path(@target, year: @past_year)

    assert_response :success
    assert_select "input[name='person_event[org_vehicle_insurance]'][type='checkbox']", count: 0
  end

  test "admin updates MVR flags" do
    sign_in_as(@admin)

    patch update_mvr_flags_person_vehicles_path(@target, year: Current.year), params: {
      person_event: {
        org_vehicle_insurance: "1",
        mvr_eligible: "1",
        ignore_mvr: "0"
      }
    }

    assert_redirected_to person_vehicles_path(@target, year: Current.year)
    event = PersonEvent.find_for_person_year(@target.id, Current.year)
    assert event.org_vehicle_insurance
    assert event.mvr_eligible
    assert_not event.ignore_mvr
  end

  test "admin updates PVR flags" do
    sign_in_as(@admin)

    patch update_pvr_flags_person_vehicles_path(@target, year: Current.year), params: {
      person_event: {
        may_request_stickers: "1",
        ignore_pvr: "1"
      }
    }

    assert_redirected_to person_vehicles_path(@target, year: Current.year)
    event = PersonEvent.find_for_person_year(@target.id, Current.year)
    assert event.may_request_stickers
    assert event.ignore_pvr
  end

  test "admin updates agreements" do
    sign_in_as(@admin)

    patch update_agreements_person_vehicles_path(@target, year: Current.year), params: {
      person_event: {
        signed_motorpool_agreement: "1",
        signed_personal_vehicle_agreement: "1"
      }
    }

    assert_redirected_to person_vehicles_path(@target, year: Current.year)
    event = PersonEvent.find_for_person_year(@target.id, Current.year)
    assert event.signed_motorpool_agreement
    assert event.signed_personal_vehicle_agreement
  end

  test "admin updates blacklist" do
    sign_in_as(@admin)

    patch update_blacklist_person_vehicles_path(@target, year: Current.year), params: {
      person: { vehicle_blacklisted: "1" }
    }

    assert_redirected_to person_vehicles_path(@target, year: Current.year)
    assert @target.reload.vehicle_blacklisted
  end

  test "vehicle manager cannot update blacklist" do
    sign_in_as(@vehicle_manager)

    patch update_blacklist_person_vehicles_path(@target, year: Current.year), params: {
      person: { vehicle_blacklisted: "1" }
    }

    assert_redirected_to person_vehicles_path(@target, year: Current.year)
    assert_equal "Admin permission required to update vehicle records.", flash[:error]
    assert_not @target.reload.vehicle_blacklisted
  end

  test "non-editor viewer cannot update MVR flags" do
    sign_in_as(@viewer)

    patch update_mvr_flags_person_vehicles_path(@target, year: Current.year), params: {
      person_event: { org_vehicle_insurance: "1" }
    }

    assert_redirected_to person_vehicles_path(@target, year: Current.year)
    assert_equal "Admin permission required to update vehicle records.", flash[:error]
    event = PersonEvent.find_for_person_year(@target.id, Current.year)
    assert_not event&.org_vehicle_insurance
  end

  test "past-year flag update is rejected" do
    sign_in_as(@admin)

    patch update_mvr_flags_person_vehicles_path(@target, year: @past_year), params: {
      person_event: { org_vehicle_insurance: "1" }
    }

    assert_redirected_to person_vehicles_path(@target, year: @past_year)
    assert_equal "Vehicle authorizations may only be changed for the current year.", flash[:error]
    event = PersonEvent.find_for_person_year(@target.id, @past_year)
    assert_not event&.org_vehicle_insurance
  end

  test "blacklisted person sees danger callout" do
    @target.update!(vehicle_blacklisted: true)
    sign_in_as(@admin)

    get person_vehicles_path(@target, year: Current.year)

    assert_response :success
    assert_select "body", text: /Vehicle Blacklisted/
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
end
# rubocop:enable Metrics/ClassLength
