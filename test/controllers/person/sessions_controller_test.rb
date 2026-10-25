# frozen_string_literal: true

require "test_helper"

class Person::SessionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    Current.reset

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @non_admin = person(:echelon_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    # NOTE: test/fixtures/sessions.yml hard-codes person_id: 1..7, but
    # test/fixtures/person.yml does not assign explicit ids, so fixture
    # person ids are hashed (e.g. person(:active_ranger).id is not 1) and
    # do not correspond to those session rows. Sessions are created directly
    # against the fixture people here instead of reusing sessions.yml.
    @session_one = @target.sessions.create!(session_id: "sess-one", ip_address: "10.0.0.1",
                                             user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                                             data: "")
    @session_two = @target.sessions.create!(session_id: "sess-two", ip_address: "10.0.0.2",
                                             user_agent: "Mozilla/5.0 Two", data: "")
  end

  teardown do
    Current.reset
  end

  test "index lists the person's login sessions for an admin" do
    sign_in_as(@admin)

    get person_sessions_path(@target)

    assert_response :success
    assert_select "td", text: "10.0.0.1"
    assert_select "td", text: "10.0.0.2"
    # The view renders parsed user agents (user_agent_format), not the raw string.
    assert_select "td", text: "Mac OS X 10.15.7 Chrome 120.0.0.0"
  end

  test "index is denied to a person-page role without admin" do
    sign_in_as(@non_admin)

    get person_sessions_path(@target)

    assert_redirected_to me_root_path
  end

  test "destroy revokes the session and redirects back with a success notice" do
    sign_in_as(@admin)

    assert_difference -> { @target.sessions.count }, -1 do
      delete person_session_path(@target, @session_one)
    end

    assert_redirected_to person_sessions_path(@target)
    assert_not Session.exists?(@session_one.id)
    assert_equal "Session revoked.", flash[:success]
  end

  test "destroy is denied to a person-page role without admin" do
    sign_in_as(@non_admin)

    assert_no_difference -> { @target.sessions.count } do
      delete person_session_path(@target, @session_one)
    end

    assert_redirected_to me_root_path
    assert Session.exists?(@session_one.id)
  end

  test "destroy is scoped to the given person and cannot revoke another person's session" do
    sign_in_as(@admin)
    other_session = @non_admin.sessions.create!(session_id: "sess-other", ip_address: "10.0.0.9",
                                                 user_agent: "Other Browser", data: "")

    begin
      delete person_session_path(@target, other_session)
      assert_response :not_found
    rescue ActiveRecord::RecordNotFound
      # Expected behavior when RecordNotFound propagates instead of being rescued into a response.
    end

    assert Session.exists?(other_session.id)
  end
end
