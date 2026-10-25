# frozen_string_literal: true

require "test_helper"

# People by Status: who reaches the page, what the index counts, and what a
# status page lists.
class People::PeopleByStatusControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  DENY_MESSAGE = "Admin role required to view people by status."

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the index" do
    get people_by_status_path

    assert_response :success
    assert_select "h1", /People by Status/
    assert_unique_dom_ids
  end

  test "someone without the admin role is turned away from the index" do
    sign_in_as(@outsider)

    get people_by_status_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error] || flash[:alert]
  end

  test "someone without the admin role is turned away from a status page" do
    sign_in_as(@outsider)

    get people_by_status_detail_path(PeopleByStatusReport.slug(Person::ACTIVE))

    assert_redirected_to me_root_path
  end

  # ---------------------------------------------------------------- index

  test "the index links a status that has people" do
    get people_by_status_path

    assert_response :success
    assert_select "a[href=?]", people_by_status_detail_path(PeopleByStatusReport.slug(Person::ACTIVE))
  end

  test "the index shows a status no one holds as a blocked row" do
    get people_by_status_path

    assert_response :success
    assert_select "a[href=?]",
                  people_by_status_detail_path(PeopleByStatusReport.slug(Person::SUSPENDED)),
                  count: 0
    assert_select "[aria-disabled=true]", /#{Person::SUSPENDED}/
  end

  test "the index total matches the number of people on file" do
    get people_by_status_path

    assert_response :success
    total = ActiveSupport::NumberHelper.number_to_delimited(Person.count)

    assert_select "body", /#{total} people/
  end

  # ------------------------------------------------------------ status page

  test "a status page lists that status's callsigns and no one else's" do
    get people_by_status_detail_path(PeopleByStatusReport.slug(Person::ACTIVE))

    assert_response :success
    assert_select "h1", /#{Person::ACTIVE}/
    assert_select "a", text: @admin.callsign
    assert_select "a", text: @outsider.callsign, count: 0
    assert_unique_dom_ids
  end

  test "a multi-word status resolves through its hyphenated slug" do
    applicant = person(:past_prospective_ranger)

    get people_by_status_detail_path("past-prospective")

    assert_response :success
    assert_select "h1", /past prospective/
    assert_select "a", text: applicant.callsign
  end

  test "an unknown slug redirects to the index with an alert" do
    get people_by_status_detail_path("shiny-pennies")

    assert_redirected_to people_by_status_path
    assert_equal "That is not a status the Clubhouse assigns.", flash[:alert]
  end

  test "a status held by one person reads in the singular" do
    @outsider.update_column(:status, Person::SUSPENDED)

    get people_by_status_path

    assert_response :success
    assert_select "a[href=?]",
                  people_by_status_detail_path(PeopleByStatusReport.slug(Person::SUSPENDED)),
                  text: /1 person/
  end

  test "the count a status shows matches the number of names on its page" do
    counted = PeopleByStatusReport.counts[Person::ACTIVE]

    get people_by_status_detail_path(PeopleByStatusReport.slug(Person::ACTIVE))

    assert_response :success
    assert_select ".callsign-list a", count: counted
  end
end
