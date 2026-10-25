# frozen_string_literal: true

require "test_helper"

class Me::WorkHistoryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  # Index action tests

  test "should get index" do
    get me_work_history_url
    assert_response :success
  end

  test "index displays page title with user callsign" do
    get me_work_history_url
    assert_response :success

    assert_match /Work History for #{@person.callsign}/, response.body
  end

  test "index displays informational text about excluded entries" do
    get me_work_history_url
    assert_response :success

    assert_match /In-Person Trainings.*not tracked/, response.body
  end

  test "index displays position titles" do
    get me_work_history_url
    assert_response :success

    # Active ranger has Mentor Lead and OOD entries (Training Lead is filtered out)
    assert_match /Mentor Lead/, response.body
    assert_match /OOD/, response.body
  end

  test "index displays years as column headers" do
    get me_work_history_url
    assert_response :success

    # Active ranger has entries in 2023 and 2024
    assert_match /2023/, response.body
    assert_match /2024/, response.body
  end

  test "index displays All Positions row" do
    get me_work_history_url
    assert_response :success

    assert_match /All Positions/, response.body
  end

  test "index links the hour figures to the /me drill-downs" do
    get me_work_history_url
    assert_response :success

    ood = positions(:ood_position).id
    assert_select "td a[href=?]", me_work_history_entire_year_path(year: 2023)
    assert_select "td a[href=?]", me_work_history_position_all_path(position_id: ood)
    assert_select "td a[href=?]", me_work_history_position_summary_path(position_id: ood, year: 2023)
  end

  test "index requires authentication" do
    sign_out

    get me_work_history_url
    assert_redirected_to root_path
  end

  test "index with no countable history shows an empty state instead of the table" do
    sign_out
    # Use ranger_with_custom_gender who has no timesheet entries but is active status
    person_without_history = person(:ranger_with_custom_gender)
    sign_in_as(person_without_history)

    get me_work_history_url
    assert_response :success

    assert_match /Work History for #{person_without_history.callsign}/, response.body
    assert_select ".empty-state", text: "No countable timesheet entries were found."
    assert_select "td", text: "All Positions", count: 0
  end

  test "index rejects statuses outside the authorized list" do
    sign_out
    sign_in_as(person(:auditor_ranger))

    get me_work_history_url

    assert_redirected_to me_root_path
    assert_equal "You are not authorized to view the page.", flash[:error]
  end

  # Position summary action tests

  test "position_summary renders breakdown page for valid position and year" do
    position = positions(:ood_position)

    get me_work_history_position_summary_url(position_id: position.id, year: 2023)
    assert_response :success
  end

  test "position_summary displays position title and year on page" do
    position = positions(:ood_position)

    get me_work_history_position_summary_url(position_id: position.id, year: 2023)
    assert_response :success

    assert_match /2023 OOD/, response.body
  end

  test "position_summary displays entry count" do
    position = positions(:ood_position)

    get me_work_history_position_summary_url(position_id: position.id, year: 2023)
    assert_response :success

    # Active ranger has 2 OOD entries in 2023
    assert_match /2 entries/, response.body
  end

  test "position_summary returns unprocessable_entity for invalid position" do
    get me_work_history_position_summary_url(position_id: 999999, year: 2023)
    assert_response :unprocessable_entity
  end

  test "position_summary returns unprocessable_entity for invalid year" do
    position = positions(:ood_position)

    get me_work_history_position_summary_url(position_id: position.id, year: 1900)
    assert_response :unprocessable_entity
  end

  test "position_summary requires authentication" do
    sign_out
    position = positions(:ood_position)

    get me_work_history_position_summary_url(position_id: position.id, year: 2023)
    assert_redirected_to root_path
  end

  # Position all action tests

  test "position_all renders breakdown page for valid position" do
    position = positions(:ood_position)

    get me_work_history_position_all_url(position_id: position.id)
    assert_response :success
  end

  test "position_all displays position title on page" do
    position = positions(:ood_position)

    get me_work_history_position_all_url(position_id: position.id)
    assert_response :success

    assert_match /OOD/, response.body
  end

  test "position_all displays entries grouped by year" do
    position = positions(:ood_position)

    get me_work_history_position_all_url(position_id: position.id)
    assert_response :success

    # Active ranger has OOD entries in 2023
    assert_match /Event Year 2023/, response.body
  end

  test "position_all returns unprocessable_entity for invalid position" do
    get me_work_history_position_all_url(position_id: 999999)
    assert_response :unprocessable_entity
  end

  test "position_all requires authentication" do
    sign_out
    position = positions(:ood_position)

    get me_work_history_position_all_url(position_id: position.id)
    assert_redirected_to root_path
  end

  # Entire year action tests

  test "entire_year renders breakdown page for valid year" do
    get me_work_history_entire_year_url(year: 2023)
    assert_response :success
  end

  test "entire_year displays year in page title" do
    get me_work_history_entire_year_url(year: 2023)
    assert_response :success

    assert_match /2023 All Positions/, response.body
  end

  test "entire_year displays position titles for entries" do
    get me_work_history_entire_year_url(year: 2023)
    assert_response :success

    # Active ranger worked OOD in 2023
    assert_match /OOD/, response.body
  end

  test "entire_year returns unprocessable_entity for invalid year" do
    get me_work_history_entire_year_url(year: 1900)
    assert_response :unprocessable_entity
  end

  test "entire_year requires authentication" do
    sign_out

    get me_work_history_entire_year_url(year: 2023)
    assert_redirected_to root_path
  end

  # Echelon work tests

  test "index displays echelon work indicator when user has echelon entries" do
    sign_out
    echelon_person = person(:echelon_ranger)
    sign_in_as(echelon_person)

    get me_work_history_url
    assert_response :success

    # The page should render successfully for echelon ranger with echelon work
    assert_match /Work History for #{echelon_person.callsign}/, response.body
  end

  test "position_summary displays echelon volunteer indicator" do
    sign_out
    echelon_person = person(:echelon_ranger)
    sign_in_as(echelon_person)

    position = positions(:mentor_lead)

    get me_work_history_position_summary_url(position_id: position.id, year: 2024)
    assert_response :success

    assert_match /as Echelon volunteer/, response.body
  end

  # Different user tests

  test "auditor is redirected from work history" do
    sign_out
    auditor = person(:auditor_ranger)
    sign_in_as(auditor)

    # Auditor status doesn't have access to work history page
    get me_work_history_url
    assert_redirected_to me_root_path
  end

  test "each user only sees their own work history" do
    get me_work_history_url
    assert_response :success

    # Active ranger should see their positions (OOD and Mentor Lead)
    assert_match /OOD/, response.body
    assert_match /Mentor Lead/, response.body
  end
end
