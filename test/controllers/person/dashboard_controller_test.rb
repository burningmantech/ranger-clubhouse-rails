# frozen_string_literal: true

require "test_helper"

# Wiring coverage for the administrative dashboard view: the controller ->
# Milestones -> Dashboard -> view path.
class Person::DashboardControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @trainer = person(:retired_ranger)
    ensure_role(Role::TRAINER, "Trainer")
    grant_role(@trainer, Role::TRAINER)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # A status that replaces the task list shows the admin the advisory itself,
  # not a note saying one exists. The page's promise is "the dashboard as they
  # currently see it", so the two status branches render the same me-side
  # partials the person is looking at -- which is the only thing exercising
  # those partials outside the me-side suite.
  test "shows the bonked advisory itself for a bonked person" do
    sign_in_as(@trainer)
    target = person(:bonked_ranger)

    get person_dashboard_path(target)

    assert_response :success
    assert_includes response.body, target.callsign
    # Both status partials share a heading, so the assertion has to be on body
    # copy only this one carries.
    assert_includes response.body, "Becoming a Black Rock Ranger can be a challenging path"
    # The advisory replaces the task list rather than sitting beside it.
    assert_not_includes response.body, "No dashboard tasks"
  end

  test "shows the past-prospective advisory itself for a past prospective person" do
    sign_in_as(@trainer)

    get person_dashboard_path(person(:past_prospective_ranger))

    assert_response :success
    assert_includes response.body, "Your Ranger application is no longer active."
    assert_not_includes response.body, "Becoming a Black Rock Ranger can be a challenging path"
  end

  # The auditor branch returns StepGroups like the others. The view used to wrap
  # them in one more group, so the progress summary called #result on a group:
  # a 500 for every auditor with a task. The heading proves tasks rendered; an
  # empty dashboard would pass without ever reaching the bug.
  test "shows an auditor's action items" do
    sign_in_as(@trainer)

    get person_dashboard_path(person(:auditor_ranger))

    assert_response :success
    assert_select "h2", text: "Auditor Action Items"
  end

  test "shows the Links & Things document the person sees" do
    sign_in_as(@trainer)
    target = person(:active_ranger)
    Document.create!(tag: Document::DASHBOARD_LINKS_RANGER_TAG, description: "Dashboard links",
                     body: %(<p><a href="https://example.com/manual">Ranger Manual</a></p>),
                     person_create_id: @trainer.id, person_update_id: @trainer.id)

    get person_dashboard_path(target)

    assert_response :success
    assert_select "section", text: /Links & Things/
    assert_select ".lexxy-content a[href=?]", "https://example.com/manual", text: "Ranger Manual"
  end

  test "denies a person without a person-management role" do
    sign_in_as(person(:active_ranger))

    get person_dashboard_path(person(:bonked_ranger))

    assert_redirected_to me_root_path
  end
end
