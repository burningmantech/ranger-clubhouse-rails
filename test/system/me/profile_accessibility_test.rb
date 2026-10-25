# frozen_string_literal: true

require "application_system_test_case"

class Me::ProfileAccessibilityTest < ApplicationSystemTestCase
  # Test accessibility, UX, and edge cases

  setup do
    @person = person(:active_ranger)
    sign_in(@person)
  end

  test "all profile edit forms have proper labels" do
    sections = {
      "identity-info" => [
        "First Name",
        "Last Name",
        "Middle Initial(s)",
        "Email Address",
        "Primary Phone"
      ],
      "mailing-address" => [
        "Street Line 1",
        "City",
        "Country",
        "State",
        "Postal Code"
      ],
      "camp" => [
        "Camp Name and Location"
      ],
      "emergency-contact" => [
        "Emergency Contact Information"
      ],
      "clothing" => [
        "T-Shirt Choice",
        "Backup T-Shirt Choice",
        "Long Sleeve Shirt Choice"
      ]
    }

    sections.each do |section, labels|
      visit me_edit_profile_section_path(section)

      labels.each do |label_text|
        assert_selector "label", text: label_text
      end
    end
  end

  test "all profile edit forms have submit and cancel buttons" do
    sections = ["identity-info", "mailing-address", "camp", "emergency-contact", "clothing"]

    sections.each do |section|
      visit me_edit_profile_section_path(section)

      # Should have submit button
      assert_button "Save"

      # Should have cancel link
      assert_link "Cancel"
    end
  end

  test "profile edit forms show helpful instructions" do
    # Identity info should show callsign change instructions
    visit me_edit_profile_section_path("identity-info")
    assert_text "Want to change your callsign?"
    assert_text "Contact the Volunteer Coordinators"

    # Mailing address should say it is not the Burner Profile address
    visit me_edit_profile_section_path("mailing-address")
    assert_text "The address in your Burner Profile is separate from the Clubhouse mailing address"

    # Camp should show example
    visit me_edit_profile_section_path("camp")
    assert_text "Example format:"
    assert_text "Camp Specificity"

    # Emergency contact should show what to include for each contact
    visit me_edit_profile_section_path("emergency-contact")
    assert_text "What should I include for off-playa contact?"
    assert_text "What should I include for on-playa contact?"

    # Clothing should show distribution info
    visit me_edit_profile_section_path("clothing")
    assert_text "claimed from the Quartermaster"
  end

  test "required fields are marked as required" do
    visit me_edit_profile_section_path("identity-info")

    # HTML5 required attribute should be present on required fields
    assert_selector "input[name='person[first_name]'][required]"
    assert_selector "input[name='person[last_name]'][required]"
    assert_selector "input[name='person[email]'][required]"

    visit me_edit_profile_section_path("mailing-address")

    assert_selector "input[name='person[street1]'][required]"
    assert_selector "input[name='person[city]'][required]"
    assert_selector "select[name='person[country]'][required]"
  end

  test "required fields are announced to screen readers, not marked by colour alone" do
    visit me_edit_profile_section_path("identity-info")

    # The label carries a visible marker as well as the required attribute, so
    # the requirement survives being read aloud or seen without colour.
    assert_selector "label[for='person_first_name']", text: /required/
  end

  test "optional fields are not marked as required" do
    visit me_edit_profile_section_path("identity-info")

    # These fields should not have required attribute
    assert_no_selector "input[name='person[mi]'][required]"
    assert_no_selector "input[name='person[preferred_name]'][required]"
    assert_no_selector "input[name='person[alt_phone]'][required]"
    assert_no_selector "input[name='person[callsign_pronounce]'][required]"
  end

  test "form fields are sized for the input they expect" do
    visit me_edit_profile_section_path("identity-info")

    # Field width is set with utility classes rather than the size attribute.
    # A middle initial gets a much narrower box than a full name.
    assert_selector "input[name='person[first_name]'].sm\\:w-48"
    assert_selector "input[name='person[last_name]'].sm\\:w-48"
    assert_selector "input[name='person[mi]'].w-20"

    visit me_edit_profile_section_path("mailing-address")

    assert_selector "input[name='person[street1]'].sm\\:w-80"
    assert_selector "input[name='person[city]'].sm\\:w-48"
    assert_selector "input[name='person[zip]'].w-28"
  end

  test "textarea fields have character counters" do
    # Camp location has maxlength and should have counter
    visit me_edit_profile_section_path("camp")

    textarea = find("textarea[name='person[camp_location]']")
    assert_equal "200", textarea["maxlength"]

    # Should have data attribute for input counter controller
    assert textarea["data-controller"]&.include?("input-counter") ||
           textarea["data-action"]&.include?("input-counter")

    # Emergency contact should also have counter
    visit me_edit_profile_section_path("emergency-contact")

    textarea = find("textarea[name='person[emergency_contact]']")
    assert_equal "200", textarea["maxlength"]
  end

  test "gender and pronouns sections have clear labels" do
    visit me_edit_profile_section_path("identity-info")

    # The two fields are grouped under one heading
    assert_selector "[role=heading]", text: "Gender & Pronouns"

    # Both fields are labelled, and the group says they are optional
    assert_selector "label", text: "Gender"
    assert_selector "label", text: "Pronouns"
    assert_text "No, both fields are optional."
  end

  test "profile index shows appropriate empty state messages" do
    person = person(:prospective_ranger)
    sign_in(person)

    visit me_profile_path

    # Should show no photo message
    assert_text "No Photo"

    # Should handle empty optional fields gracefully
    within_section "Name & Contact" do
      assert_text "Gender:"
      assert_text "Pronouns:"
      assert_text "not stated"
    end
  end

  test "edit forms maintain data on validation error" do
    visit me_edit_profile_section_path("identity-info")

    # Fill in valid data
    fill_in "Preferred First Name", with: "PreferredName"
    fill_in "Primary Phone", with: "775 555 0122"

    # Fill in invalid email
    fill_in "Email Address", with: "invalid-email"

    click_button "Save Changes"

    # Should stay on the form with the error shown. Messages here do not repeat
    # the field name, because they sit beside the field they belong to.
    assert_current_path me_edit_profile_section_path("identity-info")
    assert_selector "[role=alert]", text: I18n.t("errors.messages.email_invalid", attribute: "Email")

    # But valid data should still be in the form. The phone was read into
    # E.164 before the email check failed, and an edit field shows E.164.
    assert_field "Preferred First Name", with: "PreferredName"
    assert_field "Primary Phone", with: "+17755550122"
  end

  test "country selection interaction for address form" do
    visit me_edit_profile_section_path("mailing-address")

    # The two selects are wired to the same controller, which fills the state
    # list to match the country.
    assert_selector "select[name='person[country]'][data-country-state-target='country']"
    assert_selector "select[name='person[state]'][data-country-state-target='state']"
  end

  test "clothing section explains shirt award criteria" do
    visit me_edit_profile_section_path("clothing")

    # Should explain how shirts are earned
    assert_text "total on-duty volunteer hours, not credits"

    # Should explain claiming process
    assert_text "must be claimed from the Quartermaster on playa"
    assert_text "budget or resources to mail shirts"

    # Should explain backup choice
    assert_text "In case your first choice is unavailable"
  end

  test "profile sections use consistent styling and layout" do
    visit me_profile_path

    # All sections should use ui_section helper (box layout)
    assert_selector ".box", minimum: 5

    # Each section should have an edit link
    edit_links = all("a", text: "Edit")
    assert edit_links.count >= 5
  end

  test "flash messages appear after successful updates" do
    visit me_edit_profile_section_path("camp")

    fill_in "Camp Name and Location", with: "New Camp Info"

    click_button "Save"

    # Should show success message
    assert_text "Profile updated."
  end

  test "identity form shows gender custom field only when custom selected" do
    visit me_edit_profile_section_path("identity-info")

    # Initially the custom gender field is hidden
    assert_no_selector "#gender-custom-block", visible: true

    select "Something Else", from: "Gender"

    # Choosing it reveals the field to type one in
    assert_selector "#gender-custom-block", visible: true
  end

  test "identity form shows pronouns custom field only when custom selected" do
    visit me_edit_profile_section_path("identity-info")

    # Initially the custom pronouns field is hidden
    assert_no_selector "#pronouns-custom-block", visible: true

    select "Something else", from: "Pronouns"

    # Choosing it reveals the field to type them in
    assert_selector "#pronouns-custom-block", visible: true
  end

  test "profile page is accessible without JavaScript" do
    # This test assumes the page should work without JS (progressive enhancement)
    visit me_profile_path

    # All content should be visible
    assert_selector "h1", text: "Profile"
    assert_text "Name & Contact"

    # All edit links should work with standard navigation
    assert_link "Edit", href: me_edit_profile_section_path("identity-info")
  end

  test "form changes are not saved when clicking cancel" do
    original_first_name = @person.first_name

    visit me_edit_profile_section_path("identity-info")

    # Found by id: the label reads "First Name required", and by name alone it
    # would also match "Preferred First Name".
    fill_in "person_first_name", with: "ChangedName"

    # Click cancel
    click_link "Cancel"

    # Verify changes were not saved
    @person.reload
    assert_equal original_first_name, @person.first_name
    refute_equal "ChangedName", @person.first_name
  end
end
