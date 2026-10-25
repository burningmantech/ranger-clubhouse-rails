# frozen_string_literal: true

require "test_helper"

class Person::ApplicationsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  PRIOR_TO_2015_WARNING = /The account was created prior to 2015/

  setup do
    Rails.cache.clear

    # active_ranger owns the :created_account application fixture and is
    # created 1.year.ago, so it is a post-2015 account.
    @target = person(:active_ranger)
    @application = prospective_application(:created_account)

    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    # Holds a role in the broad PersonConcern gate but not in this page's
    # narrowed [ADMIN, VC] gate.
    @mentor = person(:ranger_with_custom_gender)
    # No application fixture points at this person.
    @no_applications = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::MENTOR, "Mentor")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@mentor, Role::MENTOR)
  end

  teardown do
    Rails.cache.clear
  end

  test "vc sees the person's applications listed" do
    sign_in_as(@vc)

    get person_applications_path(@target)

    assert_response :success
    assert_select "a[href=?]", vc_application_path(@application), text: @application.application_id
    assert_select "body", text: /Account Created/
  end

  test "admin sees the person's applications listed" do
    sign_in_as(@admin)

    get person_applications_path(@target)

    assert_response :success
    assert_select "a[href=?]", vc_application_path(@application), text: @application.application_id
  end

  test "person without the admin or vc role is denied" do
    sign_in_as(@mentor)

    get person_applications_path(@target)

    assert_redirected_to me_root_path
    assert_equal "Admin or Volunteer Coordinator role required to view applications.", flash[:error]
  end

  test "person with no applications renders the empty state" do
    sign_in_as(@vc)

    get person_applications_path(@no_applications)

    assert_response :success
    assert_select "body", text: /No applications were found for 2015 or later/
  end

  test "the prior to 2015 warning shows for an account created before 2015" do
    sign_in_as(@vc)
    @target.update_column(:created_at, Time.zone.local(2014, 6, 1))

    get person_applications_path(@target)

    assert_response :success
    assert_select "body", text: PRIOR_TO_2015_WARNING
  end

  test "the prior to 2015 warning is absent for an account created after 2015" do
    sign_in_as(@vc)

    get person_applications_path(@target)

    assert_response :success
    assert_operator @target.created_at.year, :>=, 2015
    assert_select "body", text: PRIOR_TO_2015_WARNING, count: 0
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
