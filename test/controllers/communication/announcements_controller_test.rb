# frozen_string_literal: true

require "test_helper"

class Communication::AnnouncementsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::ANNOUNCEMENT_MANAGEMENT, "Announcement Management")
    grant_role(@admin, Role::ADMIN)
    grant_role(@manager, Role::ANNOUNCEMENT_MANAGEMENT)

    @ranger_announcement = motd(:ranger_announcement)
    @applicant_announcement = motd(:applicant_announcement)
    @auditor_announcement = motd(:auditor_announcement)
    @expired_announcement = motd(:expired_ranger_announcement)

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

    get communication_announcements_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Announcement Management role required to manage announcements.", flash[:error]
  end

  test "announcement management role may manage announcements" do
    sign_in_as(@manager)

    get communication_announcements_path

    assert_response :success
    assert_match @ranger_announcement.subject, response.body
  end

  # ==========================================================================
  # Index filters
  # ==========================================================================

  test "index lists every announcement when no filter is chosen" do
    get communication_announcements_path

    assert_response :success
    [@ranger_announcement, @applicant_announcement, @auditor_announcement, @expired_announcement].each do |row|
      assert_match row.subject, response.body
    end
  end

  test "index filters by audience" do
    get communication_announcements_path(audience: "pnvs")

    assert_response :success
    assert_match @applicant_announcement.subject, response.body
    assert_no_match(/#{Regexp.escape(@ranger_announcement.subject)}/, response.body)
    assert_no_match(/#{Regexp.escape(@auditor_announcement.subject)}/, response.body)
  end

  test "index filters by status" do
    get communication_announcements_path(status: "expired")

    assert_response :success
    assert_match @expired_announcement.subject, response.body
    assert_no_match(/#{Regexp.escape(@ranger_announcement.subject)}/, response.body)
  end

  test "index ignores a filter value the page does not apply" do
    get communication_announcements_path(audience: "nonsense")

    assert_response :success
    # Falls back to "all" rather than narrowing to nothing or raising.
    assert_match @ranger_announcement.subject, response.body
    assert_match @auditor_announcement.subject, response.body
  end

  test "index sorts by expiration date" do
    get communication_announcements_path(sort: "asc")

    assert_response :success
    assert_operator response.body.index(@expired_announcement.subject),
                    :<,
                    response.body.index(@ranger_announcement.subject)
  end

  # ==========================================================================
  # Create
  # ==========================================================================

  test "create posts an announcement authored by the signed-in person" do
    assert_difference "Motd.count", 1 do
      post communication_announcements_path, params: {
        motd: {
          subject: "Radio checkout hours changed",
          message: "<div>Opens at 10:00 on Tuesday.</div>",
          expires_at: 1.week.from_now.strftime("%Y-%m-%d %H:%M:%S"),
          for_rangers: "1"
        }
      }
    end

    announcement = Motd.order(:id).last
    assert_redirected_to communication_announcements_path(anchor: "announcement-#{announcement.id}")
    assert_equal @admin.id, announcement.person_id
    assert_equal "Radio checkout hours changed", announcement.subject
  end

  test "create ignores a person_id supplied by the form" do
    post communication_announcements_path, params: {
      motd: {
        subject: "Someone else's byline",
        message: "<div>Body.</div>",
        expires_at: 1.week.from_now.strftime("%Y-%m-%d %H:%M:%S"),
        for_rangers: "1",
        person_id: @outsider.id
      }
    }

    assert_equal @admin.id, Motd.order(:id).last.person_id
  end

  test "create rejects an announcement with no audience" do
    assert_no_difference "Motd.count" do
      post communication_announcements_path, params: {
        motd: {
          subject: "No one sees this",
          message: "<div>Body.</div>",
          expires_at: 1.week.from_now.strftime("%Y-%m-%d %H:%M:%S")
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "Choose at least one audience", response.body
  end

  test "create rejects a blank expiration with a presence error" do
    assert_no_difference "Motd.count" do
      post communication_announcements_path, params: {
        motd: {
          subject: "No expiry",
          message: "<div>Body.</div>",
          expires_at: "",
          for_rangers: "1"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "can&#39;t be blank", response.body
  end

  # ==========================================================================
  # Update and delete
  # ==========================================================================

  test "update saves the changed announcement" do
    patch communication_announcement_path(@ranger_announcement), params: {
      motd: { subject: "Revised subject", message: @ranger_announcement.message,
              expires_at: @ranger_announcement.expires_at.strftime("%Y-%m-%d %H:%M:%S"),
              for_rangers: "1" }
    }

    assert_redirected_to communication_announcements_path(anchor: "announcement-#{@ranger_announcement.id}")
    assert_equal "Revised subject", @ranger_announcement.reload.subject
  end

  test "destroy removes the announcement and its read records" do
    PersonMotd.create!(person_id: @admin.id, motd_id: @ranger_announcement.id, read_at: Current.time)

    assert_difference "Motd.count", -1 do
      delete communication_announcement_path(@ranger_announcement)
    end

    assert_redirected_to communication_announcements_path
    assert_empty PersonMotd.where(motd_id: @ranger_announcement.id)
  end

  # ==========================================================================
  # Delete expired
  # ==========================================================================

  test "delete expired removes only the expired announcements" do
    assert_difference "Motd.count", -1 do
      post delete_expired_communication_announcements_path
    end

    assert_redirected_to communication_announcements_path
    assert_equal "1 expired announcement deleted.", flash[:success]
    assert Motd.exists?(@ranger_announcement.id)
  end

  test "delete expired says so when nothing has expired" do
    @expired_announcement.destroy!

    assert_no_difference "Motd.count" do
      post delete_expired_communication_announcements_path
    end

    assert_equal "No announcements have expired.", flash[:info]
  end
end
