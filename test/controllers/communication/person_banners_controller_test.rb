# frozen_string_literal: true

require "test_helper"

class Communication::PersonBannersControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @vc = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "VC")
    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)

    @vintage = person_banner(:vintage_callsign)
    @no_creator = person_banner(:no_creator_banner)
    @deleted_creator = person_banner(:deleted_creator_banner)
    @event_note = person_banner(:current_event_note)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ==========================================================================
  # Access
  # ==========================================================================

  test "denies access without an authorized role" do
    sign_in_as(@outsider)

    get communication_person_banners_path

    assert_redirected_to me_root_path
    assert_equal "Admin or VC role required to review account banners.", flash[:error]
  end

  test "allows an admin" do
    get communication_person_banners_path

    assert_response :success
  end

  test "allows a VC" do
    sign_in_as(@vc)

    get communication_person_banners_path

    assert_response :success
  end

  # ==========================================================================
  # Listing
  # ==========================================================================

  test "lists every banner when no filters are applied" do
    get communication_person_banners_path

    assert_response :success
    [@vintage, @no_creator, @deleted_creator, @event_note].each do |banner|
      assert_select "#person-banner-#{banner.id}"
    end
  end

  test "shows the message text" do
    get communication_person_banners_path

    assert_response :success
    assert_select "#person-banner-#{@event_note.id}", text: /outstanding radio/
  end

  test "renders a banner whose creator was never recorded" do
    get communication_person_banners_path

    assert_response :success
    assert_select "#person-banner-#{@no_creator.id}", text: /Posted .* by unknown/
  end

  test "renders a banner whose creator no longer exists" do
    get communication_person_banners_path

    assert_response :success
    assert_select "#person-banner-#{@deleted_creator.id}", text: /Posted .* by Deleted #999999/
  end

  test "shows the last change when a banner has been edited" do
    get communication_person_banners_path

    assert_response :success
    assert_select "#person-banner-#{@event_note.id}", text: /Changed .* by #{@vc.callsign}/
  end

  # Saving a banner stamps updated_at even when nothing was edited, so the
  # change line has to key off the editor, not the timestamp.
  test "shows no change line for a banner that was never edited" do
    assert_predicate @vintage.updated_at, :present?
    assert_nil @vintage.updater_person_id

    get communication_person_banners_path

    assert_response :success
    assert_select "#person-banner-#{@vintage.id}", text: /Changed/, count: 0
  end

  test "a freshly created banner reports no change" do
    banner = PersonBanner.create!(person: person(:retired_ranger), message: "Brand new note.")

    get communication_person_banners_path

    assert_response :success
    assert_select "#person-banner-#{banner.id}", text: /Changed/, count: 0
  end

  # ==========================================================================
  # Filters
  # ==========================================================================

  test "type filter narrows to permanent banners" do
    get communication_person_banners_path(type: "permanent")

    assert_response :success
    assert_select "#person-banner-#{@vintage.id}"
    assert_select "#person-banner-#{@event_note.id}", false
  end

  test "type filter narrows to event only banners" do
    get communication_person_banners_path(type: "event")

    assert_response :success
    assert_select "#person-banner-#{@event_note.id}"
    assert_select "#person-banner-#{@vintage.id}", false
  end

  test "year filter narrows to banners posted that year" do
    get communication_person_banners_path(year: Current.year.to_s)

    assert_response :success
    assert_select "#person-banner-#{@event_note.id}"
    assert_select "#person-banner-#{@vintage.id}", false
  end

  test "callsign filter matches part of a callsign" do
    get communication_person_banners_path(callsign: "retired")

    assert_response :success
    assert_select "#person-banner-#{@vintage.id}"
    assert_select "#person-banner-#{@event_note.id}", false
  end

  test "an unknown type is ignored rather than narrowing the list" do
    get communication_person_banners_path(type: "nonsense")

    assert_response :success
    [@vintage, @no_creator, @deleted_creator, @event_note].each do |banner|
      assert_select "#person-banner-#{banner.id}"
    end
  end

  # A year with nothing in it stays applied. Silently widening it back to every
  # year would show a list that does not match the link the reader followed.
  test "a year with no banners narrows the list to nothing" do
    get communication_person_banners_path(year: "1999")

    assert_response :success
    assert_select "#person-banner-#{@vintage.id}", false
    assert_select "body", text: /No banners matched the current filters/
    assert_select "a", text: /Year: 1999/
  end

  test "a filter arriving as a list is ignored rather than searched for" do
    get communication_person_banners_path(callsign: ["retired"], year: ["2020"])

    assert_response :success
    [@vintage, @no_creator, @deleted_creator, @event_note].each do |banner|
      assert_select "#person-banner-#{banner.id}"
    end
    assert_select "body", text: /\[/, count: 0
  end

  # "all" is the word the filter bar uses for "no filter", so a search for those
  # letters has to stay visible and removable.
  test "searching for the letters all still draws a removable chip" do
    get communication_person_banners_path(callsign: "all")

    assert_response :success
    assert_select "a", text: /Callsign: all/
  end

  # ==========================================================================
  # Chips
  # ==========================================================================

  test "no chips are drawn when nothing is filtered" do
    get communication_person_banners_path

    assert_response :success
    assert_select "a", text: /Type:/, count: 0
    assert_select "a", text: /Callsign:/, count: 0
  end

  test "removing one chip keeps the other filters" do
    get communication_person_banners_path(type: "permanent", callsign: "retired")

    assert_response :success
    assert_select "a", text: /Type: Permanent/ do |links|
      assert_includes links.first["href"], "callsign=retired"
      assert_not_includes links.first["href"], "type="
    end
  end

  # ==========================================================================
  # Grouping
  # ==========================================================================

  # Event-only notes go stale on their own, so they have to lead the page.
  test "event only banners are listed ahead of permanent ones" do
    get communication_person_banners_path

    assert_response :success
    body = response.body
    assert_operator body.index(%(person-banner-#{@event_note.id}")),
                    :<,
                    body.index(%(person-banner-#{@vintage.id}"))
  end

  test "both group headings render when both kinds are present" do
    get communication_person_banners_path

    assert_response :success
    assert_equal ["Event Only", "Permanent"], section_headings
  end

  test "a group with no banners renders no heading" do
    get communication_person_banners_path(type: "permanent")

    assert_response :success
    assert_select "#person-banner-#{@vintage.id}"
    assert_equal ["Permanent"], section_headings
  end

  private

  # ui_section renders its title as a div carrying the heading role.
  def section_headings
    css_select("div[role=heading]").map { |node| node.text.strip }
  end

  test "reports an empty result rather than an empty page" do
    get communication_person_banners_path(callsign: "no one-by-that-name")

    assert_response :success
    assert_select "#person-banner-#{@vintage.id}", false
    assert_select "body", text: /No banners matched the current filters/
  end

  # ==========================================================================
  # Counts
  # ==========================================================================

  test "the counts describe the whole list, not the filtered one" do
    get communication_person_banners_path(type: "event")

    assert_response :success
    assert_equal PersonBanner.count, @controller.view_assigns["total_count"]
    assert_equal PersonBanner.where(is_permanent: true).count, @controller.view_assigns["permanent_count"]
    assert_equal 1, @controller.view_assigns["banners"].size
  end

  test "the year menu offers every year on file even while one is chosen" do
    get communication_person_banners_path(year: Current.year.to_s)

    assert_response :success
    assert_equal PersonBanner.all.map { |banner| banner.created_at.year }.uniq.sort.reverse,
                 @controller.view_assigns["years"]
  end
end
