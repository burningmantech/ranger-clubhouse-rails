# frozen_string_literal: true

require "test_helper"

class People::OnSiteControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  NOW = Time.zone.local(2026, 9, 15, 10, 0, 0)

  setup do
    Rails.cache.clear
    Current.reset
    travel_to NOW

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    # One person free to leave, last signed out two days ago; one holding a radio.
    @leaver = person(:retired_ranger)
    @holder = person(:echelon_ranger)
    [@leaver, @holder].each { it.update_columns(on_site: true) }
    PersonOnSite.create!(person: @leaver, action: PersonOnSite::ON_SITE, created_at: NOW - 10.days)
    @entry = Timesheet.create!(person: @leaver, position: positions(:ood_position), on_duty: NOW - 2.days - 6.hours,
                               off_duty: NOW - 2.days, additional_notes: "a shift")
    PersonAsset.create!(person: @holder, asset: asset(:radio_current_year), checked_out: NOW - 5.days)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "someone without the admin role can neither see the page nor run the cleanup" do
    sign_in_as(@outsider)

    get people_on_site_path
    assert_redirected_to me_root_path
    assert_match(/admin role required/i, flash[:error])

    assert_no_difference -> { PersonOnSite.count } do
      post people_on_site_path
    end
    assert_redirected_to me_root_path
    assert @leaver.reload.on_site
  end

  test "the page lists who would be marked off site and who stays, and changes no one" do
    assert_no_difference -> { PersonOnSite.count } do
      get people_on_site_path
    end

    assert_response :success
    assert_select "h1", /On-Site Cleanup/
    assert_select "form[action='#{people_on_site_path}'][method=post] input[type=submit][value='Mark 1 Person Off Site']"
    assert_select "input[type=submit][data-turbo-confirm*='Mark 1 person off site?']"
    assert_select "tr", text: /#{@leaver.callsign}.*Sep 13, 2026 @ 10:00/m
    assert_select "tr", text: /#{@holder.callsign}.*Asset checked out/m
    assert_unique_dom_ids
    assert @leaver.reload.on_site
  end

  test "confirming marks the leaver off site at their last sign-out and leaves the holder" do
    post people_on_site_path

    assert_redirected_to people_on_site_path
    assert_equal "1 person marked off site.", flash[:success]
    assert_not @leaver.reload.on_site
    assert @holder.reload.on_site
    row = PersonOnSite.history_for(@leaver).first
    assert_equal [PersonOnSite::AUTOMATIC, @entry.reload.off_duty, @admin.id],
                 [row.reason, row.created_at, row.creator_person_id]

    follow_redirect!
    assert_select "input[type=submit]", count: 0
    assert_select "tr", text: /#{@holder.callsign}/
  end

  test "with no one on site the page says so" do
    Person.where(on_site: true).update_all(on_site: false)

    get people_on_site_path

    assert_response :success
    assert_select "body", text: /No one is marked on site\./
    assert_select "table", count: 0
  end
end
