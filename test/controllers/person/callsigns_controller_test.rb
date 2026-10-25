# frozen_string_literal: true

require "test_helper"

class Person::CallsignsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include PersonTestFactory

  setup do
    @target = person(:active_ranger)
    admin = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)
  end

  test "release resets the callsign and lands back on the edit page" do
    post release_person_callsign_path(@target)

    assert_redirected_to edit_person_callsign_path(@target)
    follow_redirect!
    assert_response :success
    @target.reload
    assert_equal "RangerT#{Current.year % 100}", @target.callsign
    assert_not @target.callsign_approved
  end

  # Clubhouse 2's PersonPolicy#releaseCallsign is Admin or VC: a Mentor edits the
  # callsign but may not release it.
  test "a Mentor is offered no Release box and is refused the release" do
    ensure_role(Role::MENTOR, "Mentor")
    mentor = create_person("Guide")
    grant_role(mentor, Role::MENTOR)
    sign_in_as(mentor)

    get edit_person_callsign_path(@target)
    assert_response :success
    assert_no_match "Release Callsign", response.body

    assert_no_changes -> { @target.reload.attributes.slice("callsign", "callsign_approved") } do
      post release_person_callsign_path(@target)
    end
    assert_redirected_to edit_person_callsign_path(@target)
    assert_equal "Admin or VC role required to release a callsign.", flash[:error]
  end

  test "a VC is offered the Release box and releases the callsign" do
    ensure_role(Role::VC, "VC")
    coordinator = create_person("Coordinator")
    grant_role(coordinator, Role::VC)
    sign_in_as(coordinator)

    get edit_person_callsign_path(@target)
    assert_match "Release Callsign", response.body

    post release_person_callsign_path(@target)

    assert_redirected_to edit_person_callsign_path(@target)
    assert_equal "RangerT#{Current.year % 100}", @target.reload.callsign
  end

  # The edit page hides the Release box for a vintage callsign; a direct POST
  # must be refused too.
  test "release refuses a vintage callsign" do
    @target.update_column(:vintage, true)

    post release_person_callsign_path(@target)

    assert_redirected_to edit_person_callsign_path(@target)
    assert_equal "The callsign is vintage and may not be released.", flash[:error]
    @target.reload
    assert_equal "TestRanger", @target.callsign
    assert @target.callsign_approved
  end
end
