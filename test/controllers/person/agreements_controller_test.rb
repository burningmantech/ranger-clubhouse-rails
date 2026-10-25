# frozen_string_literal: true

require "test_helper"

class Person::AgreementsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @event_manager = person(:echelon_ranger)
    @viewer = person(:ranger_with_custom_gender)
    @past_year = Current.year - 1

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::MENTOR, "Mentor")

    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@viewer, Role::MENTOR)

    PersonEvent.where(person_id: @target.id).delete_all
    @target.update_columns(behavioral_agreement: false)

    Agreements::DOCUMENTS.each_key do |tag|
      Document.create!(tag:, description: tag.titleize, body: "Body",
                       person_create_id: @admin.id, person_update_id: @admin.id)
    end

    # RoleManager kills all roles for EVENT_MANAGEMENT holders who have not
    # signed the Department NDA once the dept-nda document exists.
    nda = PersonEvent.first_or_new_for_person_year(@event_manager.id, Current.year)
    nda.signed_nda = true
    nda.save!(validate: false)
    RoleManager.purge_person(@event_manager.id.to_s)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "admin sees editable checkboxes, hidden badges, and the disclaimer" do
    sign_in_as(@admin)

    get person_agreements_path(@target, year: Current.year)

    assert_response :success
    assert_select "body", text: /Do Not Sign Agreements on a Ranger's Behalf/
    assert_select "input[name='agreements[behavioral-standards-agreement]'][type='checkbox']:not([disabled])", count: 1
    assert_select "input[name='agreements[sandman-affidavit]'][type='checkbox']", count: 1
    assert_select "body", text: /Hidden from Ranger/
    assert_select "input[type='submit'][value='Save Agreements']", count: 1
  end

  test "event manager gets a read-only view without hidden agreements" do
    sign_in_as(@event_manager)

    get person_agreements_path(@target, year: Current.year)

    assert_response :success
    assert_select "input[name='agreements[behavioral-standards-agreement]'][type='checkbox'][disabled]", count: 1
    assert_select "input[name='agreements[sandman-affidavit]'][type='checkbox']", count: 0
    assert_select "input[type='submit'][value='Save Agreements']", count: 0
    assert_select "body", { text: /Do not sign agreements/, count: 0 }
  end

  test "viewer without agreement access is denied" do
    sign_in_as(@viewer)

    get person_agreements_path(@target, year: Current.year)

    assert_redirected_to person_path(@target)
    assert_equal "Admin or Event Management role required to view agreements.", flash[:error]
  end

  test "past-year page is read-only even for admin" do
    sign_in_as(@admin)

    get person_agreements_path(@target, year: @past_year)

    assert_response :success
    assert_select "input[name='agreements[behavioral-standards-agreement]'][type='checkbox'][disabled]", count: 1
    assert_select "input[type='submit'][value='Save Agreements']", count: 0
  end

  test "admin checks and unchecks agreement flags with audit logs" do
    sign_in_as(@admin)

    assert_difference -> { ActionLog.where(event: "agreement-signature", target_person_id: @target.id).count }, 2 do
      patch person_agreements_path(@target, year: Current.year), params: {
        agreements: {
          Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG => "1",
          Document::MOTORPOOL_POLICY_TAG => "1"
        }
      }
    end

    assert_redirected_to person_agreements_path(@target, year: Current.year)
    assert @target.reload.behavioral_agreement
    assert PersonEvent.find_for_person_year(@target.id, Current.year).signed_motorpool_agreement

    patch person_agreements_path(@target, year: Current.year), params: {
      agreements: { Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG => "0" }
    }

    assert_not @target.reload.behavioral_agreement
  end

  test "unchanged flags do not write audit logs" do
    sign_in_as(@admin)

    assert_no_difference -> { ActionLog.where(event: "agreement-signature").count } do
      patch person_agreements_path(@target, year: Current.year), params: {
        agreements: { Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG => "0" }
      }
    end
  end

  test "event manager cannot update agreements" do
    sign_in_as(@event_manager)

    patch person_agreements_path(@target, year: Current.year), params: {
      agreements: { Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG => "1" }
    }

    assert_redirected_to person_agreements_path(@target, year: Current.year)
    assert_equal "Admin permission required to update agreements.", flash[:error]
    assert_not @target.reload.behavioral_agreement
  end

  test "past-year update is rejected even for admin" do
    sign_in_as(@admin)

    patch person_agreements_path(@target, year: @past_year), params: {
      agreements: { Document::MOTORPOOL_POLICY_TAG => "1" }
    }

    assert_redirected_to person_agreements_path(@target, year: @past_year)
    assert_equal "Agreements may only be changed for the current year.", flash[:error]
    assert_nil PersonEvent.find_for_person_year(@target.id, @past_year)
  end
end
