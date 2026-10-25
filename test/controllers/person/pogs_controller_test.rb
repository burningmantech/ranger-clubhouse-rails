# frozen_string_literal: true

require "test_helper"

class Person::PogsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include PersonTestFactory

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @event_manager = person(:echelon_ranger)
    @trainer = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    ensure_role(Role::TRAINER, "Trainer")

    grant_role(@admin, Role::ADMIN)
    # Pog writes gate on EVENT_MANAGEMENT, as Clubhouse 2's PersonPogPolicy has it.
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@trainer, Role::TRAINER)

    Current.person = @admin

    @pog_current_year = PersonPog.create!(
      person: @target, issued_by: @admin,
      pog: PersonPog::POG_MEAL, status: PersonPog::STATUS_ISSUED, notes: ""
    )
    @pog_current_year.update_column(:created_at, Time.zone.local(2026, 5, 1))

    @pog_past_year = PersonPog.create!(
      person: @target, issued_by: @admin,
      pog: PersonPog::POG_SHOWER, status: PersonPog::STATUS_REDEEMED, notes: ""
    )
    @pog_past_year.update_column(:created_at, Time.zone.local(2024, 5, 1))
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "index shows pog/status labels and the issuer's callsign for a management-role viewer" do
    sign_in_as(@trainer)

    get person_pogs_path(@target, year: Current.year)

    assert_response :success
    assert_select "th", text: "Meal Pog"
    assert_select "td", text: "Issued"
    assert_select "td", text: @admin.callsign
  end

  test "year param filters records to that year" do
    sign_in_as(@admin)

    get person_pogs_path(@target, year: 2024)

    assert_response :success
    assert_select "a", text: /Add Pog/, count: 1
    assert_select "th", text: "Shower Pog"
    assert_select "th", text: "Meal Pog", count: 0
  end

  test "create sets issued_by_id to the signed-in user and defaults issued_at" do
    sign_in_as(@event_manager)

    assert_difference("PersonPog.count", 1) do
      post person_pogs_path(@target, year: Current.year), params: {
        person_pog: { pog: PersonPog::POG_HALF_MEAL, status: PersonPog::STATUS_ISSUED, notes: "Test note" }
      }
    end

    assert_redirected_to person_pogs_path(@target, year: Current.year)

    pog = PersonPog.order(:id).last
    assert_equal @target.id, pog.person_id
    assert_equal @event_manager.id, pog.issued_by_id
    assert_equal "Test note", pog.notes
    assert_in_delta Current.time.to_i, pog.issued_at.to_i, 2
  end

  test "create ignores attempts to set person_id or issued_by_id via params" do
    sign_in_as(@event_manager)

    post person_pogs_path(@target, year: Current.year), params: {
      person_pog: {
        pog: PersonPog::POG_MEAL, status: PersonPog::STATUS_ISSUED, notes: "",
        person_id: @admin.id, issued_by_id: @admin.id
      }
    }

    pog = PersonPog.order(:id).last
    assert_equal @target.id, pog.person_id, "person_id must come from the URL, not params"
    assert_equal @event_manager.id, pog.issued_by_id, "issued_by_id must be the signed-in user, not params"
  end

  test "create with a timesheet id belonging to the person persists the link" do
    sign_in_as(@event_manager)
    entry = timesheet(:active_ranger_ood_2023_1)

    assert_difference("PersonPog.count", 1) do
      post person_pogs_path(@target, year: Current.year), params: {
        person_pog: {
          pog: PersonPog::POG_MEAL, status: PersonPog::STATUS_ISSUED, notes: "",
          timesheet_id: entry.id
        }
      }
    end

    assert_redirected_to person_pogs_path(@target, year: Current.year)
    assert_equal entry.id, PersonPog.order(:id).last.timesheet_id
  end

  test "create with someone else's timesheet id fails validation" do
    sign_in_as(@event_manager)
    other_entry = timesheet(:echelon_ranger_work_2024)
    assert_not_equal @target.id, other_entry.person_id, "fixture must belong to a different person"

    assert_no_difference("PersonPog.count") do
      post person_pogs_path(@target, year: Current.year), params: {
        person_pog: {
          pog: PersonPog::POG_MEAL, status: PersonPog::STATUS_ISSUED, notes: "",
          timesheet_id: other_entry.id
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Timesheet does not belong to person"
  end

  test "admin can update a pog" do
    sign_in_as(@admin)

    patch person_pog_path(@target, @pog_current_year, year: Current.year), params: {
      person_pog: { pog: PersonPog::POG_SHOWER, status: PersonPog::STATUS_REDEEMED, notes: "updated" }
    }

    assert_redirected_to person_pogs_path(@target, year: Current.year)
    @pog_current_year.reload
    assert_equal PersonPog::POG_SHOWER, @pog_current_year.pog
    assert_equal PersonPog::STATUS_REDEEMED, @pog_current_year.status
    assert_equal "updated", @pog_current_year.notes
  end

  test "event management role can update a pog" do
    sign_in_as(@event_manager)

    patch person_pog_path(@target, @pog_current_year, year: Current.year), params: {
      person_pog: { pog: PersonPog::POG_HALF_MEAL, status: PersonPog::STATUS_CANCELLED, notes: "" }
    }

    assert_redirected_to person_pogs_path(@target, year: Current.year)
    @pog_current_year.reload
    assert_equal PersonPog::POG_HALF_MEAL, @pog_current_year.pog
    assert_equal PersonPog::STATUS_CANCELLED, @pog_current_year.status
  end

  test "admin can destroy a pog" do
    sign_in_as(@admin)

    assert_difference("PersonPog.count", -1) do
      delete person_pog_path(@target, @pog_past_year, year: Current.year)
    end

    assert_redirected_to person_pogs_path(@target, year: Current.year)
  end

  test "event management role can destroy a pog" do
    sign_in_as(@event_manager)

    assert_difference("PersonPog.count", -1) do
      delete person_pog_path(@target, @pog_current_year, year: Current.year)
    end

    assert_redirected_to person_pogs_path(@target, year: Current.year)
  end

  # Shift Management opens person pages for the HQ window, which issues pogs through its
  # own controller; here it only reads, like every page role without Event Management.
  test "trainer and shift management can view index but are redirected away from write actions" do
    shift_manager = create_person("HqWorker")
    grant_role(shift_manager, Role::SHIFT_MANAGEMENT)

    [@trainer, shift_manager].each { |viewer| assert_refused_pog_writes(viewer) }
  end

  test "invalid pog value re-renders new with 422" do
    sign_in_as(@admin)

    assert_no_difference("PersonPog.count") do
      post person_pogs_path(@target, year: Current.year), params: {
        person_pog: { pog: "bogus", status: PersonPog::STATUS_ISSUED, notes: "" }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "is not included in the list"
  end

  test "invalid status value re-renders edit with 422" do
    sign_in_as(@admin)

    patch person_pog_path(@target, @pog_current_year, year: Current.year), params: {
      person_pog: { pog: PersonPog::POG_MEAL, status: "bogus", notes: "" }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "is not included in the list"
    assert_not_equal "bogus", @pog_current_year.reload.status
  end

  private

  def assert_refused_pog_writes(viewer)
    sign_in_as(viewer)

    get person_pogs_path(@target, year: Current.year)
    assert_response :success
    assert_select "a", text: /Add Pog/, count: 0

    get new_person_pog_path(@target, year: Current.year)
    assert_redirected_to person_pogs_path(@target, year: Current.year)
    assert_equal "Admin or Event Management role required to modify pog records.", flash[:error]

    assert_no_difference("PersonPog.count") do
      post person_pogs_path(@target, year: Current.year), params: {
        person_pog: { pog: PersonPog::POG_MEAL, status: PersonPog::STATUS_ISSUED, notes: "" }
      }
    end
    assert_redirected_to person_pogs_path(@target, year: Current.year)

    get edit_person_pog_path(@target, @pog_current_year, year: Current.year)
    assert_redirected_to person_pogs_path(@target, year: Current.year)

    patch person_pog_path(@target, @pog_current_year, year: Current.year), params: {
      person_pog: { pog: PersonPog::POG_SHOWER, status: PersonPog::STATUS_ISSUED, notes: "" }
    }
    assert_redirected_to person_pogs_path(@target, year: Current.year)
    assert_not_equal PersonPog::POG_SHOWER, @pog_current_year.reload.pog

    delete person_pog_path(@target, @pog_current_year, year: Current.year)
    assert_redirected_to person_pogs_path(@target, year: Current.year)
    assert PersonPog.exists?(@pog_current_year.id)
  end

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id:)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id:)
    RoleManager.purge_person(person.id.to_s)
  end
end
