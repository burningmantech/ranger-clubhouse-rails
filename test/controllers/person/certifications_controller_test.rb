# frozen_string_literal: true

require "test_helper"

class Person::CertificationsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @cert_manager = person(:echelon_ranger)
    @viewer = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::CERTIFICATION_MGMT, "Certification Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::MENTOR, "Mentor")

    grant_role(@admin, Role::ADMIN)
    grant_role(@cert_manager, Role::EVENT_MANAGEMENT)
    grant_role(@cert_manager, Role::CERTIFICATION_MGMT)
    grant_role(@viewer, Role::MENTOR)

    Current.person = @admin
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "manager sees the list with add and edit controls" do
    sign_in_as(@cert_manager)

    get person_certifications_path(@target)

    assert_response :success
    assert_select "body", text: /Certifications — #{@target.callsign}/
    assert_select "a", text: /Add Certification/, count: 1
    assert_select "a", text: /Edit/
    assert_select "body", text: /CPR/
  end

  test "viewer without the role sees the list but no management controls" do
    sign_in_as(@viewer)

    get person_certifications_path(@target)

    assert_response :success
    assert_select "a", text: /Add Certification/, count: 0
    assert_select "body", text: /Contact a Clubhouse Admin or Certification Manager/
    assert_select "body", text: /CPR/
  end

  test "show renders the details page" do
    sign_in_as(@viewer)

    get person_certification_path(@target, person_certification(:active_ranger_cpr))

    assert_response :success
    assert_select "body", text: /CPR-12345/
  end

  test "manager creates a certification and is recorded as the recorder" do
    sign_in_as(@cert_manager)

    assert_difference -> { PersonCertification.count }, 1 do
      post person_certifications_path(@target), params: {
        person_certification: {
          certification_id: certification(:wilderness_first_aid).id,
          card_number: "WFA-999",
          issued_on: "2026-04-01",
          trained_on: "2026-03-20",
          notes: "New record."
        }
      }
    end

    assert_redirected_to person_certifications_path(@target)
    record = PersonCertification.find_by!(card_number: "WFA-999")
    assert_equal @target.id, record.person_id
    assert_equal @cert_manager.id, record.recorder_id
  end

  test "create with a blank certification re-renders the form with an error" do
    sign_in_as(@cert_manager)

    assert_no_difference -> { PersonCertification.count } do
      post person_certifications_path(@target), params: {
        person_certification: { certification_id: "", card_number: "X" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "manager updates a certification" do
    sign_in_as(@cert_manager)
    record = person_certification(:active_ranger_cpr)

    patch person_certification_path(@target, record), params: {
      person_certification: { card_number: "CPR-EDIT" }
    }

    assert_redirected_to person_certifications_path(@target)
    assert_equal "CPR-EDIT", record.reload.card_number
  end

  test "manager deletes a certification" do
    sign_in_as(@cert_manager)
    record = person_certification(:active_ranger_cpr)

    assert_difference -> { PersonCertification.count }, -1 do
      delete person_certification_path(@target, record)
    end

    assert_redirected_to person_certifications_path(@target)
  end

  # Regression: the delete control must not end up nested inside the edit form.
  # delete_button now renders a link (data-method=delete) rather than its own
  # <form>, so the page has exactly one form (the edit form, _method=patch) plus
  # a separate delete link to the same path.
  test "edit page renders the delete control separately from the edit form" do
    sign_in_as(@cert_manager)
    record = person_certification(:active_ranger_cpr)

    get edit_person_certification_path(@target, record)

    assert_response :success
    assert_select "form[action=?]", person_certification_path(@target, record), count: 1
    assert_select "form[action=?] input[name='_method'][value='patch']", person_certification_path(@target, record), count: 1
    assert_select "a[href=?][data-turbo-method='delete']", person_certification_path(@target, record), count: 1
  end

  test "viewer without the role cannot create" do
    sign_in_as(@viewer)

    assert_no_difference -> { PersonCertification.count } do
      post person_certifications_path(@target), params: {
        person_certification: { certification_id: certification(:cpr).id }
      }
    end

    assert_redirected_to person_certifications_path(@target)
    assert_equal "Admin or Certification Management role required to administer certification records.", flash[:error]
  end

  test "viewer without the role cannot delete" do
    sign_in_as(@viewer)
    record = person_certification(:active_ranger_cpr)

    assert_no_difference -> { PersonCertification.count } do
      delete person_certification_path(@target, record)
    end

    assert_redirected_to person_certifications_path(@target)
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
