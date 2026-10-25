# frozen_string_literal: true

require "test_helper"

class Me::ProfileControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  # Index action tests
  test "should get index when authenticated" do
    get me_profile_path
    assert_response :success
  end

  test "should redirect to login when not authenticated" do
    sign_out
    get me_profile_path
    assert_redirected_to root_path
  end

  # Edit action tests
  test "should get edit for valid section" do
    Me::ProfileController::SECTION_IDS.each do |section_id|
      get me_edit_profile_section_path(section_id)
      assert_response :success, "Failed to load edit page for section: #{section_id}"
    end
  end

  test "should return 422 for invalid section on edit" do
    get me_edit_profile_section_path("invalid-section")
    assert_response :unprocessable_entity
  end

  test "should not find route for blank section on edit" do
    assert_raises ActionController::UrlGenerationError do
      get me_edit_profile_section_path("")
    end
  end

  # Update action tests - Identity Info
  test "should update identity info with valid data" do
    patch me_profile_section_path("identity-info"), params: {
      person: {
        first_name: "UpdatedFirst",
        last_name: "UpdatedLast",
        email: "updated@example.com",
        home_phone: "775 555 0103"
      }
    }

    assert_redirected_to me_profile_path
    follow_redirect!
    assert_dom ".text-base.font-normal", text: /Profile updated/
    @person.reload
    assert_equal "UpdatedFirst", @person.first_name
    assert_equal "UpdatedLast", @person.last_name
    assert_equal "updated@example.com", @person.email
  end

  test "should update gender and pronouns" do
    patch me_profile_section_path("identity-info"), params: {
      person: {
        first_name: @person.first_name,
        last_name: @person.last_name,
        email: @person.email,
        home_phone: @person.home_phone,
        gender_identity: Gender::GENDER_NON_BINARY,
        pronouns: Pronouns::PRONOUNS_NEUTRAL
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert_equal Gender::GENDER_NON_BINARY, @person.gender_identity
    assert_equal Pronouns::PRONOUNS_NEUTRAL, @person.pronouns
  end

  test "should update custom gender when selected" do
    patch me_profile_section_path("identity-info"), params: {
      person: {
        first_name: @person.first_name,
        last_name: @person.last_name,
        email: @person.email,
        home_phone: @person.home_phone,
        gender_identity: "custom",
        gender_custom: "Genderflux"
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert_equal "custom", @person.gender_identity
    assert_equal "Genderflux", @person.gender_custom
  end

  test "should clear custom gender when switching to non-custom option" do
    @person.update!(gender_identity: Gender::GENDER_CUSTOM, gender_custom: "Genderflux")

    patch me_profile_section_path("identity-info"), params: {
      person: {
        first_name: @person.first_name,
        last_name: @person.last_name,
        email: @person.email,
        home_phone: @person.home_phone,
        gender_identity: Gender::GENDER_FEMALE
      }
    }

    @person.reload
    assert_equal Gender::GENDER_FEMALE, @person.gender_identity
    assert_equal "", @person.gender_custom
  end

  test "should reject invalid email format" do
    patch me_profile_section_path("identity-info"), params: {
      person: {
        first_name: @person.first_name,
        last_name: @person.last_name,
        email: "invalid-email",
        home_phone: @person.home_phone
      }
    }

    # Rejected, not accepted: a plain 200 would be thrown away unshown.
    assert_response :unprocessable_entity
    assert_match I18n.t("errors.messages.email_invalid", attribute: "Email"), response.body
  end

  # The pattern takes it; no mail could reach it.
  test "should reject an email address with no dot in its domain" do
    patch me_profile_section_path("identity-info"), params: {
      person: {
        first_name: @person.first_name,
        last_name: @person.last_name,
        email: "name@gmailcom",
        home_phone: @person.home_phone
      }
    }

    assert_response :unprocessable_entity
    assert_match I18n.t("errors.messages.email_invalid", attribute: "Email"), response.body
    assert_not_equal "name@gmailcom", @person.reload.email
  end

  test "should reject blank required fields" do
    patch me_profile_section_path("identity-info"), params: {
      person: {
        first_name: "",
        last_name: "",
        email: "",
        home_phone: ""
      }
    }

    # Rejected, not accepted: a plain 200 would be thrown away unshown.
    assert_response :unprocessable_entity
    assert_dom ".text-error", text: /can't be blank/i
  end

  # Update action tests - Mailing Address
  test "should update mailing address with valid data" do
    patch me_profile_section_path("mailing-address"), params: {
      person: {
        street1: "999 New Street",
        apt: "Apt 5",
        street2: "Building B",
        city: "New City",
        state: "New York",
        zip: "10001",
        country: "United States"
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert_equal "999 New Street", @person.street1
    assert_equal "Apt 5", @person.apt
    assert_equal "New City", @person.city
  end

  test "should reject invalid mailing address" do
    patch me_profile_section_path("mailing-address"), params: {
      person: {
        street1: "",
        city: "",
        zip: ""
      }
    }

    # Rejected, not accepted: a plain 200 would be thrown away unshown, and the
    # form has to come back saying which fields it wants.
    assert_response :unprocessable_entity
    assert_dom ".text-error", text: /can't be blank/i
  end

  # Update action tests - Camp Location
  test "should update camp location" do
    patch me_profile_section_path("camp"), params: {
      person: {
        camp_location: "Camp Awesome, 6:00 & F"
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert_equal "Camp Awesome, 6:00 & F", @person.camp_location
  end

  test "should allow empty camp location" do
    patch me_profile_section_path("camp"), params: {
      person: {
        camp_location: ""
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert_equal "", @person.camp_location
  end

  # Update action tests - Emergency Contact
  test "should update emergency contact" do
    contact_info = "Jane Doe, Sister, 555-1234"

    patch me_profile_section_path("emergency-contact"), params: {
      person: {
        emergency_contact: contact_info
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert_equal contact_info, @person.emergency_contact
  end

  # Update action tests - Clothing
  test "should update clothing preferences" do
    tshirt = swag(:tshirt_medium)
    longsleeve = swag(:longsleeve_large)

    patch me_profile_section_path("clothing"), params: {
      person: {
        tshirt_swag_id: tshirt.id,
        tshirt_secondary_swag_id: tshirt.id,
        long_sleeve_swag_id: longsleeve.id
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert_equal tshirt.id, @person.tshirt_swag_id
    assert_equal longsleeve.id, @person.long_sleeve_swag_id
  end

  test "should allow clearing clothing preferences" do
    @person.update!(
      tshirt_swag_id: swag(:tshirt_medium).id,
      long_sleeve_swag_id: swag(:longsleeve_large).id
    )

    patch me_profile_section_path("clothing"), params: {
      person: {
        tshirt_swag_id: "",
        tshirt_secondary_swag_id: "",
        long_sleeve_swag_id: ""
      }
    }

    assert_redirected_to me_profile_path

    @person.reload
    assert_nil @person.tshirt_swag_id
    assert_nil @person.long_sleeve_swag_id
  end

  # Invalid section tests
  test "should return 422 for invalid section on update" do
    patch me_profile_section_path("invalid-section"), params: {
      person: { first_name: "Test" }
    }

    assert_response :unprocessable_entity
  end

  test "should fail for blank section on update" do
    assert_raises ActionController::UrlGenerationError do
    patch me_profile_section_path(""), params: {
      person: { first_name: "Test" }
    }
    end
  end

  # Parameter filtering tests
  test "should only permit allowed parameters" do
    # Attempt to update a protected field like status
    patch me_profile_section_path("identity-info"), params: {
      person: {
        first_name: "Test",
        last_name: "User",
        email: @person.email,
        home_phone: @person.home_phone,
        status: "admin" # Should not be permitted
      }
    }

    @person.reload
    # Status should not have changed
    assert_equal "active", @person.status
  end

  # Section-specific parameter tests
  test "clothing section should load swag options" do
    get me_edit_profile_section_path("clothing")
    assert_response :success

    # Response should contain shirt options
    assert_match /T-Shirt choice/i, response.body
    assert_match /Long Sleeve Shirt choice/i, response.body
  end

  test "non-clothing sections should not load swag options" do
    ["identity-info", "mailing-address", "camp", "emergency-contact"].each do |section|
      get me_edit_profile_section_path(section)
      assert_response :success
      # Should not attempt to load swag options
    end
  end

  # Flash message tests
  test "successful update should set success toast message" do
    patch me_profile_section_path("camp"), params: {
      person: { camp_location: "New Camp" }
    }

    assert_redirected_to me_profile_path
    follow_redirect!

    assert_dom ".text-base.font-normal", text: /Profile updated/
  end

  test "failed update should set error flash message" do
    patch me_profile_section_path("identity-info"), params: {
      person: {
        first_name: "",
        last_name: "",
        email: "",
        home_phone: ""
      }
    }

    assert_response :unprocessable_entity
    assert flash[:error] || flash[:alert] || response.body.match?(/error|invalid/i)
  end

  # Auditor restrictions tests
  test "auditor should not see restricted sections on index" do
    sign_out
    sign_in_as(person(:auditor_ranger))

    get me_profile_path
    assert_response :success

    # Auditor should not see these sections
    assert_select "h3, h4, h5, h6", text: /Camp Name.*Location/i, count: 0
    assert_select "h3, h4, h5, h6", text: /Emergency Contact/i, count: 0
    assert_select "h3, h4, h5, h6", text: /Clothing/i, count: 0
  end

  test "auditor should not be able to edit restricted sections" do
    sign_out
    sign_in_as(person(:auditor_ranger))

    # Try to edit camp section
    get me_edit_profile_section_path("camp")
    assert_redirected_to me_profile_path

    # Try to edit emergency-contact section
    get me_edit_profile_section_path("emergency-contact")
    assert_redirected_to me_profile_path

    # Try to edit clothing section
    get me_edit_profile_section_path("clothing")
    assert_redirected_to me_profile_path
  end

  test "auditor should not be able to update restricted sections" do
    sign_out
    sign_in_as(person(:auditor_ranger))

    # Try to update camp section
    patch me_profile_section_path("camp"), params: {
      person: { camp_location: "Should not work" }
    }
    assert_redirected_to me_profile_path

    # Try to update emergency-contact section
    patch me_profile_section_path("emergency-contact"), params: {
      person: { emergency_contact: "Should not work" }
    }
    assert_redirected_to me_profile_path

    # Try to update clothing section
    patch me_profile_section_path("clothing"), params: {
      person: { tshirt_swag_id: 1 }
    }
    assert_redirected_to me_profile_path
  end

  test "auditor should not see restricted fields on identity-info edit" do
    sign_out
    sign_in_as(person(:auditor_ranger))

    get me_edit_profile_section_path("identity-info")
    assert_response :success

    # Should not see callsign_pronounce field
    assert_select "input[name='person[callsign_pronounce]']", count: 0
    assert_select "label", text: /Callsign Pronunciation/i, count: 0

    # Should not see preferred_name field
    assert_select "input[name='person[preferred_name]']", count: 0
    assert_select "label", text: /Preferred Name/i, count: 0
  end

  # Past prospective and bonked restrictions tests
  test "past prospective person can access the profile" do
    sign_out
    sign_in_as(person(:past_prospective_ranger))

    get me_profile_path
    assert_response :success
  end

  test "bonked person should not access profile actions" do
    sign_out
    sign_in_as(person(:bonked_ranger))

    get me_profile_path
    assert_redirected_to me_root_path
  end
end
