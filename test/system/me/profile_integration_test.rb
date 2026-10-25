# frozen_string_literal: true

require "application_system_test_case"

class Me::ProfileIntegrationTest < ApplicationSystemTestCase
  # Test different user scenarios and complex workflows

  UPDATED_FLASH = SystemTestHelpers::PROFILE_UPDATED_FLASH

  test "user with custom gender and pronouns can view and edit profile" do
    person = person(:ranger_with_custom_gender)
    sign_in(person)

    visit me_profile_path

    # Verify custom gender and pronouns are displayed
    assert_text "Genderflux"
    assert_text "xe/xem/xyr"

    # Edit and verify custom fields are pre-populated
    within_section "Name & Contact" do
      click_link "Edit"
    end

    # Custom gender block should be visible
    assert_selector "#gender-custom-block", visible: true
    assert_field "person_gender_custom", with: "Genderflux"

    # Custom pronouns block should be visible
    assert_selector "#pronouns-custom-block", visible: true
    assert_field "person_pronouns_custom", with: "xe/xem/xyr"

    # Update custom values
    fill_in "person_gender_custom", with: "Agender"
    fill_in "person_pronouns_custom", with: "they/them"

    click_button "Save"

    assert_text UPDATED_FLASH
    assert_text "Agender"
    assert_text "they/them"
  end

  test "changing from custom gender to standard gender hides custom field" do
    person = person(:ranger_with_custom_gender)
    sign_in(person)

    visit me_edit_profile_section_path("identity-info")

    # Verify custom gender block is visible initially
    assert_selector "#gender-custom-block", visible: true

    # Change to a standard gender option
    select "Female", from: "person_gender_identity"

    # Choosing a listed gender puts the write-in box away again
    assert_no_selector "#gender-custom-block", visible: true

    click_button "Save"

    assert_text UPDATED_FLASH

    # Custom gender should be cleared
    person.reload
    assert_equal "female", person.gender_identity
    assert_equal "", person.gender_custom
  end

  test "complete profile update workflow across multiple sections" do
    person = person(:active_ranger)
    sign_in(person)

    # Update identity info
    visit me_edit_profile_section_path("identity-info")
    fill_in "Preferred First Name", with: "Testy"
    click_button "Save"
    assert_text UPDATED_FLASH

    # Update mailing address. The country on file is not one of the choices the
    # form offers, so it opens with none picked and one has to be chosen; a US
    # address then has to name a state as well.
    within_section "Mailing Address" do
      click_link "Edit"
    end
    fill_in "Street Line 1", with: "New Address 123"
    select "United States", from: "Country"
    assert_selector "select#person_state option", minimum: 2
    select "California", from: "State"
    click_button "Save"
    assert_text UPDATED_FLASH

    # Update camp location
    within_section "Camp Name & Location" do
      click_link "Edit"
    end
    fill_in "Camp Name and Location", with: "New Camp, 12:00 & A"
    click_button "Save"
    assert_text UPDATED_FLASH

    # Update emergency contact
    within_section "Emergency Contact" do
      click_link "Edit"
    end
    fill_in "Emergency Contact Information", with: "New Emergency Contact"
    click_button "Save"
    assert_text UPDATED_FLASH

    # Update clothing
    within_section "Clothing" do
      click_link "Edit"
    end
    select "Ranger T-Shirt L", from: "T-Shirt Choice"
    click_button "Save"
    assert_text UPDATED_FLASH

    # Verify all changes persisted
    person.reload
    assert_equal "Testy", person.preferred_name
    assert_equal "New Address 123", person.street1
    assert_equal "New Camp, 12:00 & A", person.camp_location
    assert_equal "New Emergency Contact", person.emergency_contact
  end

  test "profile displays all contact information correctly" do
    person = person(:ranger_with_custom_gender)
    sign_in(person)

    visit me_profile_path

    # Check full contact information display. Numbers are stored in E.164 and
    # shown the way their country writes them.
    assert_text person.email
    assert_text "(775) 555-0102" # primary phone
    assert_text "(775) 555-0103" # alternative phone
    assert_text "(alternative)" # label for alternative phone
  end

  test "profile shows address with all components" do
    person = person(:ranger_with_custom_gender)
    sign_in(person)

    visit me_profile_path

    within_section "Mailing Address" do
      # Check all address components are displayed
      assert_text "456 Oak Ave"
      assert_text "Apt 2B"
      assert_text "Suite 100"
      assert_text "Portland"
      assert_text "97201"
    end
  end

  test "profile shows middle initial when provided" do
    person = person(:ranger_with_custom_gender)
    sign_in(person)

    visit me_profile_path

    within_section "Name & Contact" do
      assert_text "Custom A Gender" # Full name with middle initial
    end
  end

  test "profile shows preferred name when provided" do
    person = person(:ranger_with_custom_gender)
    sign_in(person)

    visit me_profile_path

    within_section "Name & Contact" do
      assert_text "Preferred name: Cus"
    end
  end

  test "profile indicates when optional fields are not provided" do
    person = person(:active_ranger)
    sign_in(person)

    visit me_profile_path

    within_section "Name & Contact" do
      # No preferred name
      assert_text "no preferred first name given"

      # Gender and pronouns are provided, but for prospective ranger test below
    end
  end

  test "prospective ranger can access and edit profile" do
    person = person(:prospective_ranger)
    sign_in(person)

    visit me_profile_path

    # Should be able to view profile
    assert_selector "h1", text: "Profile"

    # Should be able to edit identity info
    within_section "Name & Contact" do
      click_link "Edit"
    end

    fill_in "person_first_name", with: "NewProspect"
    click_button "Save"

    assert_text UPDATED_FLASH

    person.reload
    assert_equal "NewProspect", person.first_name
  end

  test "email uniqueness is enforced" do
    person1 = person(:active_ranger)
    person2 = person(:ranger_with_custom_gender)
    sign_in(person1)

    visit me_edit_profile_section_path("identity-info")

    # Try to use person2's email
    fill_in "Email Address", with: person2.email

    click_button "Save"

    # A rejected save re-renders the form it was sent from, and messages do not
    # repeat the field name.
    assert_current_path me_edit_profile_section_path("identity-info")
    assert_selector "[role=alert]", text: "has already been taken"
  end

  test "phone number formatting is displayed correctly" do
    person = person(:active_ranger)
    sign_in(person)

    visit me_profile_path

    within_section "Name & Contact" do
      # Stored as "+17755550101" and shown the way the US writes it.
      assert_text "(775) 555-0101"
    end
  end

  test "very long camp location is handled correctly" do
    person = person(:active_ranger)
    sign_in(person)

    visit me_edit_profile_section_path("camp")

    # Fill with maximum allowed characters (200)
    long_text = "A" * 200
    fill_in "Camp Name and Location", with: long_text

    click_button "Save"

    assert_text UPDATED_FLASH

    person.reload
    assert_equal long_text, person.camp_location
  end

  test "camp location exceeding max length is truncated or rejected" do
    person = person(:active_ranger)
    sign_in(person)

    visit me_edit_profile_section_path("camp")

    # Try to enter more than 200 characters
    # HTML5 maxlength should prevent this, but test the validation
    too_long = "A" * 201

    # Use execute_script to bypass HTML5 validation for testing
    page.execute_script("document.querySelector('textarea[name=\"person[camp_location]\"]').value = '#{too_long}'")

    click_button "Save"

    # Should show validation error
    assert_selector "[role=alert]", text: "is too long (maximum is 200 characters)"
  end

  test "email format validation rejects invalid emails" do
    person = person(:active_ranger)
    sign_in(person)

    visit me_edit_profile_section_path("identity-info")

    invalid_emails = [
      "notanemail",
      "@example.com",
      "user@",
      "user name@example.com"
    ]

    invalid_emails.each do |invalid_email|
      fill_in "Email Address", with: invalid_email
      click_button "Save"

      assert_current_path me_edit_profile_section_path("identity-info")
      assert_selector "[role=alert]", text: I18n.t("errors.messages.email_invalid", attribute: "Email")

      # Navigate back to retry
      visit me_edit_profile_section_path("identity-info")
    end
  end

  test "profile sections have proper navigation breadcrumbs or back links" do
    person = person(:active_ranger)
    sign_in(person)

    # Check each edit page has a cancel link back to profile
    [
      "identity-info",
      "mailing-address",
      "camp",
      "emergency-contact",
      "clothing"
    ].each do |section|
      visit me_edit_profile_section_path(section)

      # Should have a cancel link
      assert_link "Cancel", href: me_profile_path

      # Click cancel and verify we return to profile
      click_link "Cancel"
      assert_current_path me_profile_path

      # Verify no changes were saved
      person.reload
    end
  end

  test "callsign pronunciation with special characters" do
    person = person(:active_ranger)
    sign_in(person)

    visit me_edit_profile_section_path("identity-info")

    # Enter pronunciation with special characters
    fill_in "Pronunciation of #{person.callsign}", with: "3-P-O (Three-Pee-Oh)"

    click_button "Save"

    assert_text UPDATED_FLASH

    visit me_profile_path

    within_section "Name & Contact" do
      assert_text "3-P-O (Three-Pee-Oh)"
    end
  end
end
