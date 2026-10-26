# frozen_string_literal: true

require "test_helper"

class Admin::ActionLogsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear
    ActionLog.delete_all

    @admin = person(:auditor_ranger)
    @non_admin = person(:active_ranger)
    @actor = person(:active_ranger)
    @target = person(:prospective_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)
  end

  teardown do
    Rails.cache.clear
  end

  test "admin can view action logs and expandable rows" do
    slot = Slot.create!(
      position: positions(:mentor_lead),
      begins: Time.zone.local(2026, 4, 9, 9, 0, 0),
      ends: Time.zone.local(2026, 4, 9, 11, 0, 0),
      max: 10
    )

    row = ActionLog.create!(
      event: "auth-login",
      person: @actor,
      target_person: @target,
      ip: "127.0.0.1",
      user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Chrome/123.0 Safari/537.36",
      message: "A" * 80,
      data: {
        "team_id" => teams(:mentor_cadre).id,
        "position_id" => positions(:mentor_lead).id,
        "slot_id" => slot.id
      },
      created_at: Time.zone.local(2026, 4, 9, 8, 30, 15)
    )

    sign_in_as(@admin)

    get admin_action_logs_path

    assert_response :success
    assert_select "h1", text: /Action Logs/
    assert_select "label", text: /Starts At/
    assert_select "label", text: /Ends At/
    assert_select "tr#action-log-detail-#{row.id}.hidden", count: 1
    assert_select "a[href=?]", person_path(@actor), text: @actor.callsign
    assert_select "a[href=?]", person_path(@target), text: @target.callsign
    assert_select "button[data-controller='toggle'][data-toggle-dom-id-value=?]", "action-log-detail-#{row.id}", count: 1
    assert_select "button[data-controller='toggle'][data-toggle-dom-id-value=?] .fa-chevron-down", "action-log-detail-#{row.id}", count: 1
    assert_select ".action-log-inline-metadata", text: /Slot:\s+#\d+ · Mentor Lead/, count: 1
    assert_select ".action-log-inline-metadata", text: /Position:\s+#\d+ · Mentor Lead/, count: 1
    assert_select ".action-log-inline-metadata", text: /Team:\s+#\d+ · Mentor Cadre/, count: 1
    assert_select "[data-controller='read-more']", count: 1
    assert_select "dt", text: /IP address/
    assert_select "dt", text: /User agent/
    assert_select "tr#action-log-detail-#{row.id}", text: /\bSlots\b/, count: 0
    assert_select "tr#action-log-detail-#{row.id}", text: /\bPositions\b/, count: 0
    assert_select "tr#action-log-detail-#{row.id}", text: /\bTeams\b/, count: 0
  end

  # The header is stored as it arrived, and no account is needed to store one:
  # RequestLogger writes this row for a signed-out view of the login page.
  test "a user agent holding markup is shown as text" do
    user_agent = "Mozilla/5.0 (Macintosh) Chrome/123.0 <script>alert(1)</script><img src=x onerror=alert(2)>"
    row = ActionLog.create!(event: "page-visit", message: "/", user_agent:)

    sign_in_as(@admin)

    get admin_action_logs_path

    assert_response :success
    assert_select "tr#action-log-detail-#{row.id} dl" do
      assert_select "script", count: 0
      assert_select "[onerror]", count: 0
      assert_select "dd", text: user_agent, count: 1
      assert_select "dd", text: "Chrome • 123.0 • macOS", count: 1
    end
  end

  test "non-admin is denied" do
    sign_in_as(@non_admin)

    get admin_action_logs_path

    assert_redirected_to me_root_path
  end

  test "unknown callsign returns empty results without querying" do
    sign_in_as(@admin)

    get admin_action_logs_path, params: {
      filter: {
        person_callsign: "UnknownCallsign"
      }
    }

    assert_response :success
    assert_select "body", text: /No Action Log entries matched the current filters/
  end

  test "filter params persist in pager links" do
    55.times do |idx|
      ActionLog.create!(
        event: "auth-login",
        person: @actor,
        target_person: @target,
        message: "persist me",
        data: {},
        created_at: Time.zone.local(2026, 4, 9, 8, 0, idx)
      )
    end

    sign_in_as(@admin)

    get admin_action_logs_path, params: {
      filter: {
        person_callsign: @actor.callsign,
        event_filters: ["auth-login"],
        message: "persist me"
      }
    }

    assert_response :success
    assert_select "a[href*='filter%5Bperson_callsign%5D=#{CGI.escape(@actor.callsign)}'][href*='filter%5Bevent_filters%5D%5B%5D=auth-login'][href*='filter%5Bmessage%5D=persist+me'][href*='filter%5Bpage%5D=2']",
                  text: /Next Page/
  end

  test "event checkboxes and event name are combined as an or query" do
    ActionLog.create!(
      event: "auth-login",
      person: @actor,
      target_person: @target,
      message: "login event",
      data: {},
      created_at: Time.zone.local(2026, 4, 9, 8, 0, 0)
    )
    ActionLog.create!(
      event: "custom-action",
      person: @actor,
      target_person: @target,
      message: "custom event",
      data: {},
      created_at: Time.zone.local(2026, 4, 9, 8, 1, 0)
    )

    sign_in_as(@admin)

    get admin_action_logs_path, params: {
      filter: {
        event_filters: ["auth-login"],
        event_name: "custom-action"
      }
    }

    assert_response :success
    assert_select "body", text: /login event/
    assert_select "body", text: /custom event/
  end

  # Time.zone.parse reads "26" as the 26th of this month. A time that names no
  # whole date must narrow nothing, and draw no chip claiming it did.
  test "a partial date narrows nothing and draws no chip" do
    ActionLog.create!(event: "auth-login", person: @actor, target_person: @target, message: "an old login",
                      data: {}, created_at: Time.zone.local(2020, 1, 1, 8, 0, 0))

    sign_in_as(@admin)

    get admin_action_logs_path, params: { filter: { start_time: "26" } }

    assert_response :success
    assert_select "body", text: /an old login/
    assert_select "a[aria-label^='Remove filter: From']", 0
  end

  test "a non-hash filter param is ignored rather than raising" do
    sign_in_as(@admin)

    get admin_action_logs_path, params: { filter: "x" }
    assert_response :success

    get admin_action_logs_path, params: { filter: ["a", "b"] }
    assert_response :success

    get "#{admin_action_logs_path}?filter"
    assert_response :success
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
