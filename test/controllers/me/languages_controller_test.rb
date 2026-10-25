# frozen_string_literal: true

require "test_helper"

class Me::LanguagesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  # Index tests

  test "should get index" do
    get me_profile_languages_url
    assert_response :success
  end

  test "index renders languages in a responsive table" do
    PersonLanguage.create!(
      person: @person,
      language_name: "Spanish",
      proficiency: PersonLanguage::PROFICIENCY_FLUENT
    )

    get me_profile_languages_url

    assert_response :success
    assert_select "div.table-container > table.responsive-table"
    assert_select "th[scope=row][data-label=Language]", text: /Spanish/
    assert_select "td[data-label=Proficiency]", text: /Fluent/
  end

  test "index requires authentication" do
    sign_out

    get me_profile_languages_url
    assert_redirected_to root_path
  end

  # New tests

  test "should get new" do
    get new_me_profile_language_url
    assert_response :success
  end

  test "new displays language form" do
    get new_me_profile_language_url
    assert_response :success

    assert_match /language/i, response.body
  end

  # Create tests

  test "should create language" do
    assert_difference("PersonLanguage.count", 1) do
      post me_profile_languages_url, params: {
        person_language: {
          language_name: "Spanish",
          proficiency: PersonLanguage::PROFICIENCY_FLUENT
        }
      }
    end

    assert_redirected_to me_profile_languages_url
    assert_equal "Language created.", flash[:success]
  end

  test "should create language with custom name" do
    assert_difference("PersonLanguage.count", 1) do
      post me_profile_languages_url, params: {
        person_language: {
          language_name: PersonLanguage::LANGUAGE_NAME_CUSTOM,
          language_custom: "Klingon",
          proficiency: PersonLanguage::PROFICIENCY_BASIC
        }
      }
    end

    assert_redirected_to me_profile_languages_url
  end

  test "create fails with invalid proficiency" do
    assert_no_difference("PersonLanguage.count") do
      post me_profile_languages_url, params: {
        person_language: {
          language_name: "French",
          proficiency: "invalid_level"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create requires language name" do
    assert_no_difference("PersonLanguage.count") do
      post me_profile_languages_url, params: {
        person_language: {
          language_name: "",
          proficiency: PersonLanguage::PROFICIENCY_FLUENT
        }
      }
    end

    assert_response :unprocessable_entity
  end

  # Edit tests

  test "should get edit" do
    language = PersonLanguage.create!(
      person: @person,
      language_name: "German",
      proficiency: PersonLanguage::PROFICIENCY_INTERMEDIATE
    )

    get edit_me_profile_language_url(language)
    assert_response :success
  end

  # Update tests

  test "should update language" do
    language = PersonLanguage.create!(
      person: @person,
      language_name: "Italian",
      proficiency: PersonLanguage::PROFICIENCY_BASIC
    )

    patch me_profile_language_url(language), params: {
      person_language: {
        proficiency: PersonLanguage::PROFICIENCY_FLUENT
      }
    }

    assert_redirected_to me_profile_languages_url
    assert_equal "Language updated.", flash[:success]

    language.reload
    assert_equal PersonLanguage::PROFICIENCY_FLUENT, language.proficiency
  end

  test "update fails with invalid data" do
    language = PersonLanguage.create!(
      person: @person,
      language_name: "Portuguese",
      proficiency: PersonLanguage::PROFICIENCY_INTERMEDIATE
    )

    patch me_profile_language_url(language), params: {
      person_language: {
        proficiency: "invalid"
      }
    }

    assert_response :unprocessable_entity
  end

  # Destroy tests

  test "should destroy language" do
    language = PersonLanguage.create!(
      person: @person,
      language_name: "Japanese",
      proficiency: PersonLanguage::PROFICIENCY_FLUENT
    )

    assert_difference("PersonLanguage.count", -1) do
      delete me_profile_language_url(language)
    end

    assert_redirected_to me_profile_languages_url
    assert_equal "Language deleted.", flash[:success]
  end

  test "cannot access other user's language" do
    other_person = person(:ranger_with_custom_gender)
    language = PersonLanguage.create!(
      person: other_person,
      language_name: "Russian",
      proficiency: PersonLanguage::PROFICIENCY_FLUENT
    )

    # Should raise RecordNotFound or return an error
    begin
      get edit_me_profile_language_url(language)
      # If no exception, should get an error response
      assert [404, 422, 500].include?(response.status)
    rescue ActiveRecord::RecordNotFound
      # Expected behavior
    end
  end
end
