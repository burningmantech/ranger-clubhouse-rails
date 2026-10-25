# frozen_string_literal: true

require "test_helper"

class Me::AwardsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  test "should get index" do
    get me_awards_url
    assert_response :success
  end

  test "index displays team awards in response" do
    get me_awards_url
    assert_response :success

    # Should show Khaki Delegation team
    assert_match /Khaki Delegation/, response.body
    # Should show DIRT Team
    assert_match /DIRT Team/, response.body
  end

  test "index displays position awards in response" do
    get me_awards_url
    assert_response :success

    # Should show Training Lead
    assert_match /Training Lead/, response.body
    # Should show OOD
    assert_match /OOD/, response.body
  end

  test "index displays special service awards in response" do
    get me_awards_url
    assert_response :success

    # Should show Outstanding Service Award
    assert_match /Outstanding Service Award/, response.body
    # Should show Volunteer Excellence
    assert_match /Volunteer Excellence/, response.body
  end

  test "index shows year ranges for awards" do
    get me_awards_url
    assert_response :success

    # Khaki has years 2020, 2021, 2023 which should show as "2020 - 2021, 2023"
    assert_match /2020 - 2021, 2023/, response.body
    # Training Lead has 2021, 2022 which should show as "2021 - 2022"
    assert_match /2021 - 2022/, response.body
  end

  test "index shows service years section" do
    get me_awards_url
    assert_response :success

    # Should have service years text
    assert_match /service years/, response.body
  end

  test "index shows no service years for awards without service year flag" do
    get me_awards_url
    assert_response :success

    # Should have "no service years" text for awards that don't grant service years
    assert_match /no service years/, response.body
  end

  test "index shows informational alert about awards" do
    get me_awards_url
    assert_response :success

    # Should have the informational text
    assert_match /Year-round volunteer efforts/, response.body
    assert_match /Many currently reflect activity/, response.body
    assert_match /only from 2020 onward/, response.body
  end

  test "index shows section headings" do
    get me_awards_url
    assert_response :success

    assert_match /Cadre \/ Delegation and Selected Team Recognition/, response.body
    assert_match /Special Position Recognition/, response.body
    assert_match /Special Service Recognition/, response.body
  end

  test "index includes user callsign in title" do
    get me_awards_url
    assert_response :success

    assert_match /Service Recognition/, response.body
  end

  test "index with no awards shows appropriate message" do
    # Sign in as a user with no awards
    sign_out
    person_without_awards = person(:prospective_ranger)
    sign_in_as(person_without_awards)

    get me_awards_url
    assert_response :success

    assert_match /No service recognition awards have been granted yet/, response.body
  end

  test "index requires authentication" do
    sign_out

    get me_awards_url
    assert_redirected_to root_path
  end

  test "index only shows current user's awards" do
    get me_awards_url
    assert_response :success

    # Should show TestRanger's awards
    assert_match /Khaki Delegation/, response.body
    assert_match /DIRT Team/, response.body
  end
end
