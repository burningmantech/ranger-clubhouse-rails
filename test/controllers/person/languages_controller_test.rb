# frozen_string_literal: true

require "test_helper"

class Person::LanguagesControllerTest < ActionDispatch::IntegrationTest
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

    PersonLanguage.create!(
      person: @target,
      language_name: "Spanish",
      proficiency: PersonLanguage::PROFICIENCY_FLUENT
    )
  end

  teardown do
    Rails.cache.clear
  end

  test "admin can view languages index" do
    sign_in_as(@admin)
    get person_profile_languages_path(@target)
    assert_response :success
    assert_match "Spanish", response.body
  end

  test "vc can view languages index" do
    sign_in_as(@vc)
    get person_profile_languages_path(@target)
    assert_response :success
  end

  test "event_management can view languages index" do
    sign_in_as(@em)
    get person_profile_languages_path(@target)
    assert_response :success
  end

  test "user without qualifying role cannot access" do
    sign_in_as(@no_one)
    get person_profile_languages_path(@target)
    assert_redirected_to me_root_path
  end

  test "admin can GET new" do
    sign_in_as(@admin)
    get new_person_profile_language_path(@target)
    assert_response :success
  end

  test "vc can create a language" do
    sign_in_as(@vc)
    assert_difference -> { @target.person_language.count }, 1 do
      post person_profile_languages_path(@target),
           params: { person_language: { language_name: "French", proficiency: PersonLanguage::PROFICIENCY_BASIC } }
    end
    assert_redirected_to person_profile_languages_path(@target)
  end

  test "event_management cannot GET new" do
    sign_in_as(@em)
    get new_person_profile_language_path(@target)
    assert_redirected_to person_profile_path(@target)
  end

  test "event_management cannot create" do
    sign_in_as(@em)
    assert_no_difference -> { @target.person_language.count } do
      post person_profile_languages_path(@target),
           params: { person_language: { language_name: "French", proficiency: PersonLanguage::PROFICIENCY_BASIC } }
    end
    assert_redirected_to person_profile_path(@target)
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
