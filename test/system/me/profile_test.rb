# frozen_string_literal: true

require "application_system_test_case"

class Me::ProfileTest < ApplicationSystemTestCase
  UPDATED_FLASH = SystemTestHelpers::PROFILE_UPDATED_FLASH
  SUBMIT_ERROR_FLASH = "The information could not be saved due to form errors."

  setup do
    @person = person(:active_ranger)
    sign_in(@person)
  end

  test "viewing profile index shows all profile sections" do
    visit me_profile_path

    # Wait for content to load
    assert_text "Clubhouse", wait: 5

    # Check page title
    assert_selector "h1", text: "Profile"

    # Check that all sections are present
    assert_text "Name & Contact"
    assert_text "Mailing Address"
    assert_text "Camp Name & Location"
    assert_text "Emergency Contact"
    assert_text "Languages"
    assert_text "Clothing"

    # Check that personal info is displayed
    assert_text @person.first_name
    assert_text @person.last_name
    assert_text @person.email
    assert_text @person.street1
    assert_text @person.city
  end

  test "profile index shows BMID photo section" do
    visit me_profile_path

    assert_text "BMID Photo"
    # Should show "No Photo" text when no photo exists
    assert_text "No Photo"
    assert_link "Upload Photo"
  end

  # Identity Info Tests
  test "editing identity information with valid data" do
    visit me_profile_path

    # Find and click the edit link for identity info
    within_section "Name & Contact" do
      click_link "Edit"
    end

    assert_current_path me_edit_profile_section_path("identity-info")
    assert_selector "h1", text: "Edit Identity & Contact Information"

    # Filled by id where the label alone would also match another field.
    fill_in "person_first_name", with: "UpdatedFirst"
    fill_in "person_last_name", with: "UpdatedLast"
    fill_in "Middle Initial(s)", with: "M"
    fill_in "Preferred First Name", with: "Uffy"
    fill_in "Email Address", with: "updated@example.com"
    fill_in "Primary Phone", with: "775 555 0120"
    fill_in "Alternative Phone", with: "(775) 555-0121 cell"

    select "Non-Binary", from: "person_gender_identity"
    select "They / Them / Their", from: "person_pronouns"

    click_button "Save"

    # Should redirect back to profile index
    assert_current_path me_profile_path
    assert_text UPDATED_FLASH

    # Verify changes are displayed
    assert_text "UpdatedFirst"
    assert_text "UpdatedLast"
    assert_text "Uffy"
    assert_text "updated@example.com"

    # Stored in E.164 whatever was typed, the note after the number dropped,
    # and shown the way the US writes it.
    assert_text "(775) 555-0120"
    @person.reload
    assert_equal "+17755550120", @person.home_phone
    assert_equal "+17755550121", @person.alt_phone
  end

  test "editing identity information with custom gender" do
    visit me_profile_path

    within_section "Name & Contact" do
      click_link "Edit"
    end

    # Select custom gender
    select "Something Else", from: "person_gender_identity"

    # Custom gender field should appear
    assert_selector "#gender-custom-block", visible: true
    fill_in "person_gender_custom", with: "Non-binary femme"

    click_button "Save"

    assert_current_path me_profile_path
    assert_text UPDATED_FLASH
    assert_text "Non-binary femme"
  end

  test "editing identity information with custom pronouns" do
    visit me_profile_path

    within_section "Name & Contact" do
      click_link "Edit"
    end

    # Select custom pronouns
    select "Something else", from: "person_pronouns"

    # Custom pronouns field should appear
    assert_selector "#pronouns-custom-block", visible: true
    fill_in "person_pronouns_custom", with: "ze/zim/zir"

    click_button "Save"

    assert_current_path me_profile_path
    assert_text UPDATED_FLASH
    assert_text "ze/zim/zir"
  end

  test "editing identity information with callsign pronunciation" do
    visit me_profile_path

    within_section "Name & Contact" do
      click_link "Edit"
    end

    fill_in "Pronunciation of #{@person.callsign}", with: "TEST-rayn-jer"

    click_button "Save"

    assert_current_path me_profile_path
    assert_text UPDATED_FLASH
    assert_text "TEST-rayn-jer"
  end

  test "identity information will not submit while a required field is blank" do
    visit me_edit_profile_section_path("identity-info")

    fill_in "person_first_name", with: ""

    click_button "Save"

    # The browser stops the submit, so nothing is saved and the form stays put.
    # The banner a rejected save puts up is what tells the two apart: it is only
    # there if the form reached the Clubhouse and came back.
    assert_current_path me_edit_profile_section_path("identity-info")
    assert_no_text SUBMIT_ERROR_FLASH
    assert_not page.evaluate_script("document.querySelector('#person_first_name').checkValidity()")
    assert_equal @person.first_name, @person.reload.first_name
  end

  test "identity information validation - email format" do
    visit me_edit_profile_section_path("identity-info")

    fill_in "Email Address", with: "invalid-email"

    click_button "Save"

    # A rejected save re-renders the form it was sent from. Messages do not
    # repeat the field name, because they sit beside the field they belong to.
    assert_current_path me_edit_profile_section_path("identity-info")
    assert_selector "[role=alert]", text: I18n.t("errors.messages.email_invalid", attribute: "Email")
  end

  test "canceling identity information edit returns to profile" do
    visit me_edit_profile_section_path("identity-info")

    click_link "Cancel"

    assert_current_path me_profile_path
  end

  # Mailing Address Tests
  test "editing mailing address with valid data" do
    visit me_profile_path

    within_section "Mailing Address" do
      click_link "Edit"
    end

    assert_current_path me_edit_profile_section_path("mailing-address")
    assert_selector "h1", text: "Edit Mailing Address"

    # Fill in address fields
    fill_in "Street Line 1", with: "999 Updated Street"
    fill_in "Apt / Unit", with: "Unit 5B"
    fill_in "Street Line 2", with: "Building C"
    fill_in "City", with: "New City"
    fill_in "Postal Code", with: "90210"

    # Choosing the country fills the state list, and a US address has to name a
    # state, so it is picked from the refreshed list.
    select "United States", from: "Country"
    assert_selector "select#person_state option", minimum: 2
    select "California", from: "State"

    click_button "Save"

    assert_current_path me_profile_path
    assert_text UPDATED_FLASH

    # Verify changes
    assert_text "999 Updated Street"
    assert_text "Unit 5B"
    assert_text "Building C"
    assert_text "New City"
    assert_text "90210"
  end

  test "mailing address will not submit while a required field is blank" do
    visit me_edit_profile_section_path("mailing-address")

    fill_in "Street Line 1", with: ""

    click_button "Save"

    assert_current_path me_edit_profile_section_path("mailing-address")
    assert_no_text SUBMIT_ERROR_FLASH
    assert_not page.evaluate_script("document.querySelector('#person_street1').checkValidity()")
    assert_equal @person.street1, @person.reload.street1
  end

  test "canceling mailing address edit returns to profile" do
    visit me_edit_profile_section_path("mailing-address")

    click_link "Cancel"

    assert_current_path me_profile_path
  end

  # Camp Location Tests
  test "editing camp location with valid data" do
    visit me_profile_path

    within_section "Camp Name & Location" do
      click_link "Edit"
    end

    assert_current_path me_edit_profile_section_path("camp")
    assert_selector "h1", text: "Edit Camp Name & Location"

    # Fill in camp location
    fill_in "Camp Name and Location", with: "Camp Awesome, 6:00 & F, Playa side"

    click_button "Save"

    assert_current_path me_profile_path
    assert_text UPDATED_FLASH
    assert_text "Camp Awesome, 6:00 & F, Playa side"
  end

  test "camp location can be cleared" do
    visit me_edit_profile_section_path("camp")

    fill_in "Camp Name and Location", with: ""

    click_button "Save"

    assert_current_path me_profile_path
    assert_text UPDATED_FLASH
  end

  test "canceling camp location edit returns to profile" do
    visit me_edit_profile_section_path("camp")

    click_link "Cancel"

    assert_current_path me_profile_path
  end

  # Emergency Contact Tests
  test "editing emergency contact with valid data" do
    visit me_profile_path

    within_section "Emergency Contact" do
      click_link "Edit"
    end

    assert_current_path me_edit_profile_section_path("emergency-contact")
    assert_selector "h1", text: "Edit Emergency Contact Information"

    # Fill in emergency contact
    emergency_info = "Off-Playa: Jane Doe, Sister, 555-1234, jane@example.com\nOn-Playa: John Playa, Camp mate, Camp XYZ at 3:00 & A"
    fill_in "Emergency Contact Information", with: emergency_info

    click_button "Save"

    assert_current_path me_profile_path
    assert_text UPDATED_FLASH
    assert_text "Jane Doe"
    assert_text "John Playa"
  end

  test "emergency contact can be cleared" do
    visit me_edit_profile_section_path("emergency-contact")

    fill_in "Emergency Contact Information", with: ""

    click_button "Save"

    assert_current_path me_profile_path
    assert_text UPDATED_FLASH
  end

  test "canceling emergency contact edit returns to profile" do
    visit me_edit_profile_section_path("emergency-contact")

    click_link "Cancel"

    assert_current_path me_profile_path
  end

  # Clothing Tests
  test "editing clothing choices with valid selections" do
    visit me_profile_path

    within_section "Clothing" do
      click_link "Edit"
    end

    assert_current_path me_edit_profile_section_path("clothing")
    assert_selector "h1", text: "Edit Clothing Choices"

    # Select shirt options
    select "Ranger T-Shirt M", from: "T-Shirt Choice"
    select "Ranger T-Shirt L", from: "Backup T-Shirt Choice"
    select "Ranger Long Sleeve M", from: "Long Sleeve Shirt Choice"

    click_button "Save"

    assert_current_path me_profile_path
    assert_text UPDATED_FLASH
  end

  test "clothing section shows inactive shirts are not available" do
    visit me_edit_profile_section_path("clothing")

    # Inactive shirts should not appear in the select options
    assert_no_selector "option", text: "Inactive T-Shirt M"
  end

  test "clothing section allows not selected option" do
    visit me_edit_profile_section_path("clothing")

    # Should have "Not Selected" option
    assert_selector "option", text: "Not Selected"

    select "Not Selected", from: "T-Shirt Choice"

    click_button "Save"

    assert_current_path me_profile_path
    assert_text UPDATED_FLASH
  end

  test "canceling clothing edit returns to profile" do
    visit me_edit_profile_section_path("clothing")

    click_link "Cancel"

    assert_current_path me_profile_path
  end

  # A section name the Clubhouse does not know is answered with an empty 422,
  # which a browser cannot show and Capybara cannot read a status from. Both
  # the read and the write side are covered in
  # test/controllers/me/profile_controller_test.rb instead.
end
