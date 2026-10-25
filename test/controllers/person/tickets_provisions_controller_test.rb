# frozen_string_literal: true

require "test_helper"

class Person::TicketsProvisionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @ticketing_admin = person(:echelon_ranger)
    @viewer = person(:ranger_with_custom_gender)

    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Docs")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    grant_role(@ticketing_admin, Role::EDIT_ACCESS_DOCS)
    grant_role(@viewer, Role::EVENT_MANAGEMENT)

    Current.person = @ticketing_admin
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "ticketing admin sees the hub with documents and provisions" do
    sign_in_as(@ticketing_admin)

    get person_tickets_provisions_path(@target)

    assert_response :success
    assert_select "body", text: /Access Documents/
    assert_select "body", text: /RAD-#{access_document(:ar_spt).id}/
    assert_select "body", text: /RP-#{provision(:ar_meals).id}/
    # Unlike the BMID page, the provisions section stays expanded here.
    assert_no_match "provisions-toggle", response.body
    assert_select "#provisions-collapsible-body:not(.hidden)"
  end

  test "person-page user without the ticketing role is denied" do
    sign_in_as(@viewer)

    get person_tickets_provisions_path(@target)

    assert_redirected_to me_root_path
  end

  test "show all reveals expired documents hidden by default" do
    expired = AccessDocument.create!(
      person_id: @target.id,
      type: AccessDocument::SPT,
      status: AccessDocument::EXPIRED,
      source_year: 2020,
      expiry_date: "2021-09-15",
      delivery_method: AccessDocument::DELIVERY_NONE
    )
    sign_in_as(@ticketing_admin)

    get person_tickets_provisions_path(@target)
    assert_response :success
    assert_no_match "RAD-#{expired.id}", response.body

    get person_tickets_provisions_path(@target, documents: "all")
    assert_response :success
    assert_match "RAD-#{expired.id}", response.body
  end

  test "dashboard renders the view-as-person page without stamping a visit" do
    sign_in_as(@ticketing_admin)

    get person_tickets_provisions_dashboard_path(@target)

    assert_response :success
    assert_match "This is how the Me &gt; Tickets &amp; Stuff page appears", response.body

    event = PersonEvent.find_by(person_id: @target.id, year: Time.zone.now.year)
    assert_nil event&.ticketing_last_visited_at
  end

  test "dashboard renders the finished overview for a member with a claimed Staff Credential" do
    access_document(:ar_staff_credential).update_columns(status: AccessDocument::CLAIMED)
    finish_ticketing_for(@target)
    sign_in_as(@ticketing_admin)

    get person_tickets_provisions_dashboard_path(@target)

    assert_response :success
    assert_match "Pickup at Staff Credentialing", response.body
  end

  test "dashboard renders the finished overview for a member with a claimed Special Price Ticket" do
    access_document(:ar_spt).update_columns(status: AccessDocument::CLAIMED, delivery_method: AccessDocument::DELIVERY_POSTAL)
    finish_ticketing_for(@target)
    sign_in_as(@ticketing_admin)

    get person_tickets_provisions_dashboard_path(@target)

    assert_response :success
    assert_match "Mailed via USPS Standard", response.body
  end

  test "dashboard renders the closed-period overview" do
    setting(:ticketing_period).update!(value: TicketingInfo::PERIOD_CLOSED)
    sign_in_as(@ticketing_admin)

    get person_tickets_provisions_dashboard_path(@target)

    assert_response :success
    assert_match "Ranger Ticketing Is Closed", response.body
  end

  private

  def finish_ticketing_for(person)
    event = PersonEvent.first_or_new_for_person_year(person.id, Time.zone.now.year)
    event.ticketing_finished_at = Time.zone.now
    event.save!(validate: false)
  end
end
