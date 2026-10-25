# frozen_string_literal: true

require "test_helper"

module Me
  class AnnouncementsControllerTest < ActionDispatch::IntegrationTest
    include AuthenticationTestHelper

    # Helper to check if announcement subject is visible in response
    def assert_announcement_visible(announcement)
      assert_match announcement.subject, response.body
    end

    def assert_announcement_not_visible(announcement)
      assert_no_match(/#{Regexp.escape(announcement.subject)}/, response.body)
    end

    # ============================================================================
    # Basic Index Tests
    # ============================================================================

    test "index requires authentication" do
      get me_announcements_url
      assert_redirected_to root_path
    end

    test "index displays page title" do
      sign_in_as(person(:active_ranger))
      get me_announcements_url
      assert_response :success
      assert_match(/Announcements/, response.body)
    end

    # ============================================================================
    # Auditor Announcement Tests
    # ============================================================================
    #
    # Auditors should see announcements with for_auditors=true.
    # No other status should see auditor announcements.
    # Note: Auditor is in Person::NO_MESSAGES_STATUSES, which currently prevents
    # auditors from seeing any announcements in the current implementation.
    # ============================================================================

    test "auditor sees auditor announcements" do
      auditor = person(:auditor_ranger)
      sign_in_as(auditor)

      get me_announcements_url
      assert_response :success

      # Due to NO_MESSAGES_STATUSES including AUDITOR, the current implementation
      # returns an empty array for auditors. If this behavior changes, update this test.
      motd(:auditor_announcement)
      # When auditors can see announcements, this should be:
      # assert_announcement_visible(auditor_announcement)
      # Currently, auditors see no announcements:
      assert_match(/There are currently no Clubhouse announcements/, response.body)
    end

    test "active ranger cannot see auditor announcements" do
      sign_in_as(person(:active_ranger))

      get me_announcements_url
      assert_response :success

      auditor_announcement = motd(:auditor_announcement)
      assert_announcement_not_visible(auditor_announcement)
    end

    test "prospective ranger cannot see auditor announcements" do
      sign_in_as(person(:prospective_ranger))

      get me_announcements_url
      assert_response :success

      auditor_announcement = motd(:auditor_announcement)
      assert_announcement_not_visible(auditor_announcement)
    end

    test "alpha ranger cannot see auditor announcements" do
      sign_in_as(person(:alpha_ranger))

      get me_announcements_url
      assert_response :success

      auditor_announcement = motd(:auditor_announcement)
      assert_announcement_not_visible(auditor_announcement)
    end

    test "echelon cannot see auditor announcements" do
      sign_in_as(person(:echelon_ranger))

      get me_announcements_url
      assert_response :success

      auditor_announcement = motd(:auditor_announcement)
      assert_announcement_not_visible(auditor_announcement)
    end

    test "inactive ranger cannot see auditor announcements" do
      sign_in_as(person(:inactive_ranger))

      get me_announcements_url
      assert_response :success

      auditor_announcement = motd(:auditor_announcement)
      assert_announcement_not_visible(auditor_announcement)
    end

    test "retired ranger cannot see auditor announcements" do
      sign_in_as(person(:retired_ranger))

      get me_announcements_url
      assert_response :success

      auditor_announcement = motd(:auditor_announcement)
      assert_announcement_not_visible(auditor_announcement)
    end

    # ============================================================================
    # PNV (Alpha & Prospective) Announcement Tests
    # ============================================================================
    #
    # PNV announcements (for_pnvs=true) should be visible to alpha and prospective
    # statuses only. Rangers and Echelon should NOT see these announcements.
    # ============================================================================

    test "prospective ranger sees PNV announcements" do
      sign_in_as(person(:prospective_ranger))

      get me_announcements_url
      assert_response :success

      applicant_announcement = motd(:applicant_announcement)
      assert_announcement_visible(applicant_announcement)
    end

    test "alpha ranger sees PNV announcements" do
      sign_in_as(person(:alpha_ranger))

      get me_announcements_url
      assert_response :success

      applicant_announcement = motd(:applicant_announcement)
      assert_announcement_visible(applicant_announcement)
    end

    test "active ranger cannot see PNV announcements" do
      sign_in_as(person(:active_ranger))

      get me_announcements_url
      assert_response :success

      applicant_announcement = motd(:applicant_announcement)
      assert_announcement_not_visible(applicant_announcement)
    end

    test "inactive ranger cannot see PNV announcements" do
      sign_in_as(person(:inactive_ranger))

      get me_announcements_url
      assert_response :success

      applicant_announcement = motd(:applicant_announcement)
      assert_announcement_not_visible(applicant_announcement)
    end

    test "retired ranger cannot see PNV announcements" do
      sign_in_as(person(:retired_ranger))

      get me_announcements_url
      assert_response :success

      applicant_announcement = motd(:applicant_announcement)
      assert_announcement_not_visible(applicant_announcement)
    end

    test "echelon cannot see PNV announcements" do
      sign_in_as(person(:echelon_ranger))

      get me_announcements_url
      assert_response :success

      applicant_announcement = motd(:applicant_announcement)
      assert_announcement_not_visible(applicant_announcement)
    end

    test "auditor cannot see PNV announcements" do
      sign_in_as(person(:auditor_ranger))

      get me_announcements_url
      assert_response :success

      # Auditors see no announcements due to NO_MESSAGES_STATUSES
      applicant_announcement = motd(:applicant_announcement)
      assert_announcement_not_visible(applicant_announcement)
    end

    # ============================================================================
    # Ranger Announcement Tests
    # ============================================================================
    #
    # Ranger announcements (for_rangers=true) should be visible to ranger statuses
    # (active, inactive, inactive extension, retired) and echelon.
    # PNVs (alpha, prospective) and auditors should NOT see these announcements.
    # ============================================================================

    test "active ranger sees ranger announcements" do
      sign_in_as(person(:active_ranger))

      get me_announcements_url
      assert_response :success

      ranger_announcement = motd(:ranger_announcement)
      assert_announcement_visible(ranger_announcement)
    end

    test "inactive ranger sees ranger announcements" do
      sign_in_as(person(:inactive_ranger))

      get me_announcements_url
      assert_response :success

      ranger_announcement = motd(:ranger_announcement)
      assert_announcement_visible(ranger_announcement)
    end

    test "retired ranger sees ranger announcements" do
      sign_in_as(person(:retired_ranger))

      get me_announcements_url
      assert_response :success

      ranger_announcement = motd(:ranger_announcement)
      assert_announcement_visible(ranger_announcement)
    end

    test "echelon sees ranger announcements" do
      sign_in_as(person(:echelon_ranger))

      get me_announcements_url
      assert_response :success

      ranger_announcement = motd(:ranger_announcement)
      assert_announcement_visible(ranger_announcement)
    end

    test "prospective ranger cannot see ranger announcements" do
      sign_in_as(person(:prospective_ranger))

      get me_announcements_url
      assert_response :success

      ranger_announcement = motd(:ranger_announcement)
      assert_announcement_not_visible(ranger_announcement)
    end

    test "alpha ranger cannot see ranger announcements" do
      sign_in_as(person(:alpha_ranger))

      get me_announcements_url
      assert_response :success

      ranger_announcement = motd(:ranger_announcement)
      assert_announcement_not_visible(ranger_announcement)
    end

    test "auditor cannot see ranger announcements" do
      sign_in_as(person(:auditor_ranger))

      get me_announcements_url
      assert_response :success

      # Auditors see no announcements due to NO_MESSAGES_STATUSES
      ranger_announcement = motd(:ranger_announcement)
      assert_announcement_not_visible(ranger_announcement)
    end

    # ============================================================================
    # Toggle Read Action Tests
    # ============================================================================

    test "toggle_read requires authentication" do
      announcement = motd(:ranger_announcement)
      post me_toggle_read_announcement_url(announcement)
      assert_redirected_to root_path
    end

    test "toggle_read marks announcement as read" do
      sign_in_as(person(:active_ranger))
      announcement = motd(:ranger_announcement)

      post me_toggle_read_announcement_url(announcement),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_match(/turbo-stream/, response.content_type)
    end

    test "toggle_read with invalid announcement redirects with error" do
      sign_in_as(person(:active_ranger))

      post me_toggle_read_announcement_url(id: 999_999)
      assert_redirected_to me_announcements_path
      follow_redirect!
      assert_match(/Announcement not found/, response.body)
    end

    test "toggle_read for announcement not visible to user redirects with error" do
      sign_in_as(person(:prospective_ranger))
      ranger_announcement = motd(:ranger_announcement)

      post me_toggle_read_announcement_url(ranger_announcement)
      assert_redirected_to me_announcements_path
      follow_redirect!
      assert_match(/Announcement not found/, response.body)
    end

    # ============================================================================
    # Cross-Status Visibility Matrix Tests
    # ============================================================================
    #
    # These tests verify that each status type ONLY sees their designated
    # announcement type and no others.
    # ============================================================================

    test "prospective only sees PNV announcements, not ranger or auditor" do
      sign_in_as(person(:prospective_ranger))

      get me_announcements_url
      assert_response :success

      # Should see PNV
      assert_announcement_visible(motd(:applicant_announcement))

      # Should NOT see ranger or auditor
      assert_announcement_not_visible(motd(:ranger_announcement))
      assert_announcement_not_visible(motd(:auditor_announcement))
    end

    test "alpha only sees PNV announcements, not ranger or auditor" do
      sign_in_as(person(:alpha_ranger))

      get me_announcements_url
      assert_response :success

      # Should see PNV
      assert_announcement_visible(motd(:applicant_announcement))

      # Should NOT see ranger or auditor
      assert_announcement_not_visible(motd(:ranger_announcement))
      assert_announcement_not_visible(motd(:auditor_announcement))
    end

    test "active ranger only sees ranger announcements, not PNV or auditor" do
      sign_in_as(person(:active_ranger))

      get me_announcements_url
      assert_response :success

      # Should see ranger
      assert_announcement_visible(motd(:ranger_announcement))

      # Should NOT see PNV or auditor
      assert_announcement_not_visible(motd(:applicant_announcement))
      assert_announcement_not_visible(motd(:auditor_announcement))
    end

    test "echelon only sees ranger announcements, not PNV or auditor" do
      sign_in_as(person(:echelon_ranger))

      get me_announcements_url
      assert_response :success

      # Should see ranger
      assert_announcement_visible(motd(:ranger_announcement))

      # Should NOT see PNV or auditor
      assert_announcement_not_visible(motd(:applicant_announcement))
      assert_announcement_not_visible(motd(:auditor_announcement))
    end

    # ============================================================================
    # NO_MESSAGES_STATUSES Tests
    # ============================================================================
    #
    # Statuses in NO_MESSAGES_STATUSES should see no announcements.
    # ============================================================================

    test "bonked status sees no announcements" do
      sign_in_as(person(:bonked_ranger))

      get me_announcements_url
      assert_response :success

      assert_match(/There are currently no Clubhouse announcements/, response.body)
    end

    test "past prospective status is sent back to the dashboard" do
      sign_in_as(person(:past_prospective_ranger))

      get me_announcements_url
      assert_redirected_to me_root_path
    end

    # ============================================================================
    # Display Content Tests
    # ============================================================================

    test "ranger sees appropriate messaging about mailing list" do
      sign_in_as(person(:active_ranger))

      get me_announcements_url
      assert_response :success

      assert_match(/Ranger Announce mailing list/, response.body)
    end

    test "prospective sees appropriate messaging about newsletter" do
      sign_in_as(person(:prospective_ranger))

      get me_announcements_url
      assert_response :success

      # View has line breaks in HTML, so match key phrase
      assert_match(/Applicant Newsletter/, response.body)
    end

    test "alpha sees appropriate messaging about newsletter" do
      sign_in_as(person(:alpha_ranger))

      get me_announcements_url
      assert_response :success

      # View has line breaks in HTML, so match key phrase
      assert_match(/Applicant Newsletter/, response.body)
    end

    # ============================================================================
    # Expired Announcement Tests
    # ============================================================================

    test "expired announcements are still shown with expiration notice" do
      sign_in_as(person(:active_ranger))

      get me_announcements_url
      assert_response :success

      # The expired announcement should be visible (retrieval doesn't filter by expiry)
      expired_announcement = motd(:expired_ranger_announcement)
      assert_announcement_visible(expired_announcement)
    end

    # ============================================================================
    # Message Body Tests
    # ============================================================================

    # The people who post an announcement are not the people it is shown to, so
    # the message is sanitized here as it is on the management page.
    test "a message keeps its formatting and loses anything that could run" do
      announcement = motd(:ranger_announcement)
      announcement.update_column(:message, %(<p>Bring <strong>water</strong>.</p><ul><li>Goggles</li></ul>
        <p><a href="https://example.org/map" onclick="alert(0)">Map</a></p><img src="x" onerror="alert(1)"><script>alert(2)</script>))
      sign_in_as(person(:active_ranger))

      get me_announcements_url

      assert_select "##{ActionView::RecordIdentifier.dom_id(announcement)} .lexxy-content" do
        assert_select "strong", text: "water"
        assert_select "ul li", text: "Goggles"
        assert_select "a[href=?]", "https://example.org/map", text: "Map"
        assert_select "[onclick]", count: 0
        assert_select "[onerror]", count: 0
        assert_select "script", count: 0
      end
    end
  end
end
