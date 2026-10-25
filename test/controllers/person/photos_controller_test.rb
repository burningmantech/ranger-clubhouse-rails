# frozen_string_literal: true

require "test_helper"

class Person::PhotosControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    @em = person(:ranger_with_custom_gender)
    @no_one = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@em, Role::EVENT_MANAGEMENT)
  end

  teardown do
    Rails.cache.clear
  end

  test "admin can GET new" do
    sign_in_as(@admin)
    get new_person_photo_path(@target)
    assert_response :success
  end

  test "vc can GET new" do
    sign_in_as(@vc)
    get new_person_photo_path(@target)
    assert_response :success
  end

  test "new is upload-only with no Take Selfie tab" do
    sign_in_as(@admin)
    get new_person_photo_path(@target)
    assert_response :success

    assert_select "#tab-camera", count: 0
    assert_select "#panel-camera", count: 0
  end

  test "event_management cannot access photo upload" do
    sign_in_as(@em)
    get new_person_photo_path(@target)
    assert_redirected_to me_root_path
  end

  test "user without qualifying role cannot access" do
    sign_in_as(@no_one)
    get new_person_photo_path(@target)
    assert_redirected_to me_root_path
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id:)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id:)
    RoleManager.purge_person(person.id.to_s)
  end
end
