# frozen_string_literal: true

require "test_helper"

class Person::BmidsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @bmid_admin = person(:echelon_ranger)
    @viewer = person(:ranger_with_custom_gender)

    ensure_role(Role::EDIT_BMIDS, "Edit BMIDs")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    grant_role(@bmid_admin, Role::EDIT_BMIDS)
    grant_role(@viewer, Role::EVENT_MANAGEMENT)

    Current.person = @bmid_admin
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "show renders a create form when no BMID exists yet" do
    sign_in_as(@bmid_admin)
    assert_nil Bmid.find_for_person_year(@target.id, 2026)

    get person_bmid_path(@target)

    assert_response :success
    assert_select "body", text: /2026 BMID/
    assert_match "Save BMID", response.body
    # Provisions section is shared with Tickets & Provisions.
    assert_match "RP-#{provision(:ar_meals).id}", response.body
  end

  test "the provisions section starts collapsed on the BMID page" do
    sign_in_as(@bmid_admin)

    get person_bmid_path(@target)

    assert_response :success
    assert_match "provisions-toggle", response.body
    assert_select "#provisions-collapsible-body.hidden"
  end

  test "show renders an update form when a BMID exists" do
    Bmid.create!(person_id: @target.id, year: 2026, status: Bmid::IN_PREP, title1: "Shift Lead")
    sign_in_as(@bmid_admin)

    get person_bmid_path(@target)

    assert_response :success
    assert_match "Save BMID", response.body
    assert_match "Shift Lead", response.body
  end

  test "create inserts the badge and snapshots current provisions" do
    sign_in_as(@bmid_admin)

    assert_difference "Bmid.where(person_id: #{@target.id}, year: 2026).count", 1 do
      post person_bmid_path(@target), params: {
        bmid: { status: Bmid::READY_TO_PRINT, title1: "Shift Lead", team: "Green Dot" }
      }
    end

    assert_redirected_to person_bmid_path(@target)

    bmid = Bmid.find_for_person_year(@target.id, 2026)
    assert_equal Bmid::READY_TO_PRINT, bmid.status
    assert_equal "Shift Lead", bmid.title1
    # active_ranger has an event-week meal and a shower provision (available).
    assert_equal "event", bmid.meals
    assert bmid.showers
  end

  test "update changes an existing badge" do
    bmid = Bmid.create!(person_id: @target.id, year: 2026, status: Bmid::IN_PREP)
    sign_in_as(@bmid_admin)

    assert_no_difference "Bmid.count" do
      patch person_bmid_path(@target), params: {
        bmid: { status: Bmid::DO_NOT_PRINT, notes: "Not rangering this year." }
      }
    end

    assert_redirected_to person_bmid_path(@target)

    bmid.reload
    assert_equal Bmid::DO_NOT_PRINT, bmid.status
    assert_includes bmid.notes, "Not rangering"
  end

  test "a user without the BMID role is denied" do
    sign_in_as(@viewer)

    get person_bmid_path(@target)

    assert_redirected_to me_root_path
  end

  test "an Edit-Access-Docs-only user is denied the BMID page" do
    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Docs")
    grant_role(@viewer, Role::EDIT_ACCESS_DOCS)
    sign_in_as(@viewer)

    get person_bmid_path(@target)

    assert_redirected_to me_root_path
  end

  test "saving the badge propagates the SAP date to the person's SAP documents" do
    sign_in_as(@bmid_admin)

    post person_bmid_path(@target), params: {
      bmid: { status: Bmid::IN_PREP, admission_date: "2026-08-20" }
    }

    assert_redirected_to person_bmid_path(@target)
    # active_ranger has a Staff Credential and a SAP, both changeable (qualified).
    assert_equal Date.new(2026, 8, 20), access_document(:ar_sap).reload.access_date&.to_date
    assert_equal Date.new(2026, 8, 20), access_document(:ar_staff_credential).reload.access_date&.to_date
  end

  test "saving with 'any time' sets any-time access on the SAP documents" do
    sign_in_as(@bmid_admin)

    post person_bmid_path(@target), params: {
      bmid: { status: Bmid::IN_PREP, admission_date: AccessDocument::ADMISSION_ANY }
    }

    assert_redirected_to person_bmid_path(@target)
    assert access_document(:ar_sap).reload.access_any_time
  end

  test "an invalid status is rejected without persisting" do
    sign_in_as(@bmid_admin)

    assert_no_difference "Bmid.count" do
      post person_bmid_path(@target), params: { bmid: { status: "bogus" } }
    end

    assert_response :unprocessable_entity
  end

  test "show all reveals expired provisions hidden by default on the BMID page" do
    expired = Provision.create!(
      person_id: @target.id, type: Provision::WET_SPOT, status: Provision::EXPIRED,
      source_year: 2020, expires_on: "2021-09-15"
    )
    sign_in_as(@bmid_admin)

    get person_bmid_path(@target)
    assert_response :success
    assert_no_match "RP-#{expired.id}", response.body

    get person_bmid_path(@target, provisions: "all")
    assert_response :success
    assert_match "RP-#{expired.id}", response.body
  end

  test "the not-qualified warning uses Echelon wording for Echelon volunteers" do
    sign_in_as(@bmid_admin)

    get person_bmid_path(@bmid_admin) # echelon_ranger, viewing their own BMID

    assert_response :success
    assert_match "signed up for any shifts", response.body
  end

  test "provision links from the BMID page return to the BMID page" do
    sign_in_as(@bmid_admin)

    patch person_provision_path(@target, provision(:ar_meals), origin: "bmid"), params: {
      provision: { status: Provision::CLAIMED }
    }

    assert_redirected_to person_bmid_path(@target)
  end

  test "deleting a provision from the BMID page returns to the BMID page" do
    sign_in_as(@bmid_admin)

    delete person_provision_path(@target, provision(:ar_shower), origin: "bmid")

    assert_redirected_to person_bmid_path(@target)
  end
end
