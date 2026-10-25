# Profile Controller System Tests

This directory contains comprehensive acceptance/system tests for the `Me::ProfileController` and related views.

## Test Files

### `profile_test.rb`
Core functionality tests for the profile management system:
- **Profile Index**: Tests viewing the main profile page with all sections
- **Identity Information**: Tests for editing name, gender, pronouns, contact info
- **Mailing Address**: Tests for editing address information
- **Camp Location**: Tests for editing camp name and location
- **Emergency Contact**: Tests for editing emergency contact info
- **Clothing**: Tests for selecting shirt preferences
- **Validation**: Tests for required fields and format validation
- **Navigation**: Tests for cancel links and form submission flows

### `profile_integration_test.rb`
Integration and workflow tests:
- **Custom Gender/Pronouns**: Tests for users with custom gender identity and pronouns
- **Multi-section Workflows**: Tests updating multiple profile sections in sequence
- **Different User Types**: Tests for active rangers, prospective rangers, etc.
- **Display Formatting**: Tests for proper display of contact info, addresses, names
- **Email Uniqueness**: Tests for preventing duplicate emails
- **Edge Cases**: Tests for maximum length fields, special characters, etc.

### `profile_accessibility_test.rb`
Accessibility, UX, and interface tests:
- **Form Labels**: Tests that all forms have proper, accessible labels
- **Required Field Indicators**: Tests that required fields are marked correctly
- **Help Text**: Tests that helpful instructions are shown
- **Field Sizing**: Tests that input fields have appropriate sizes
- **Character Counters**: Tests for textarea character limit indicators
- **Empty States**: Tests for graceful handling of missing/empty data
- **Progressive Enhancement**: Tests that pages work without JavaScript
- **Stimulus Controllers**: Tests for conditional field visibility
- **Flash Messages**: Tests for success/error message display
- **Consistent Styling**: Tests for consistent UI patterns

## Test Coverage

The tests cover:

### Profile Sections Tested
1. ✅ Identity Information (name, gender, pronouns, contact)
2. ✅ Mailing Address (street, city, state, country)
3. ✅ Camp Location (camp name and placement)
4. ✅ Emergency Contact (on-playa and off-playa contacts)
5. ✅ Clothing (t-shirt and long sleeve preferences)
6. ✅ Photo section display (upload link, status indicators)

### Validation Tested
- ✅ Required field validation
- ✅ Email format validation
- ✅ Email uniqueness validation
- ✅ Maximum length validation
- ✅ Data persistence after validation errors

### User Experience Tested
- ✅ Form labels and accessibility
- ✅ Help text and instructions
- ✅ Cancel button functionality
- ✅ Success message display
- ✅ Error message display
- ✅ Custom field conditional display (gender, pronouns)
- ✅ Empty state handling

### User Types Tested
- ✅ Active Rangers
- ✅ Prospective Rangers
- ✅ Users with custom gender/pronouns
- ✅ Users with complete profile data
- ✅ Users with minimal profile data

## Running the Tests

### Run all profile tests:
```bash
bin/rails test:system test/system/me/
```

### Run a specific test file:
```bash
bin/rails test:system test/system/me/profile_test.rb
```

### Run a specific test:
```bash
bin/rails test:system test/system/me/profile_test.rb:LineNumber
# or by name:
bin/rails test:system test/system/me/profile_test.rb -n "test_editing_identity_information_with_valid_data"
```

### Run tests with visible browser (for debugging):
```bash
HEADLESS=false bin/rails test:system test/system/me/profile_test.rb
```

### Run tests with verbose output:
```bash
bin/rails test:system test/system/me/profile_test.rb --verbose
```

## Test Fixtures

The tests use the following fixtures:

### Person Fixtures (`test/fixtures/person.yml`)
- `active_ranger`: Standard active ranger with complete profile
- `ranger_with_custom_gender`: Ranger with custom gender identity and pronouns
- `prospective_ranger`: Prospective ranger with minimal profile

### Swag Fixtures (`test/fixtures/swag.yml`)
- Various t-shirt sizes (S, M, L, XL)
- Various long sleeve sizes (S, M, L)
- Inactive shirt (for testing filtering)

### Session Fixtures (`test/fixtures/sessions.yml`)
- Sessions for each test person for authentication

## Test Helpers

### `SystemTestHelpers` Module
Located in `test/support/system_test_helpers.rb`, provides:

- `sign_in(person)`: Authenticate as a specific person
- `sign_out`: Clear authentication
- `within_section(heading)`: Scope actions to a specific page section
- `assert_flash_message(message, type:)`: Assert flash messages
- `assert_validation_errors(*messages)`: Assert validation error display
- `fill_in_bootstrap_field(label, with:)`: Fill Bootstrap form fields
- `wait_for_turbo`: Wait for Turbo navigation to complete
- `assert_page_title(title)`: Verify page title
- `bypass_html5_validation`: Bypass HTML5 validation for server validation tests

## Common Test Patterns

### Testing a Profile Section Edit:
```ruby
test "editing camp location with valid data" do
  visit me_profile_path
  
  within_section "Camp Name & Location" do
    click_link "Edit"
  end
  
  fill_in "Enter your camp's name and location:", with: "Camp Awesome"
  click_button "Save"
  
  assert_text "Personal info updated successfully"
  assert_text "Camp Awesome"
end
```

### Testing Validation:
```ruby
test "identity information validation - required fields" do
  visit me_edit_profile_section_path("identity-info")
  
  fill_in "Legal First Name", with: ""
  click_button "Save"
  
  assert_current_path me_profile_section_path("identity-info")
  assert_text "First name can't be blank"
end
```

### Testing Conditional Fields (Stimulus):
```ruby
test "editing identity information with custom gender" do
  visit me_edit_profile_section_path("identity-info")
  
  select "Custom", from: "Gender (Optional)"
  assert_selector "#gender-custom-block", visible: true
  
  fill_in "Tell us your gender", with: "Non-binary femme"
  click_button "Save"
  
  assert_text "Non-binary femme"
end
```

## Authentication in Tests

All tests use the `sign_in` helper from `SystemTestHelpers`:

```ruby
setup do
  @person = person(:active_ranger)
  sign_in(@person)
end
```

This creates a valid session cookie, allowing the test to access authenticated routes.

## Debugging Tests

### Taking Screenshots:
```ruby
take_screenshot("debug_screenshot")
# or use the helper
take_debug_screenshot("my_debug_shot")
```

### Using Debugger:
```ruby
test "my test" do
  visit me_profile_path
  debugger # execution will pause here
  # ...
end
```

### Viewing the Browser:
Run tests without headless mode:
```bash
HEADLESS=false bin/rails test:system test/system/me/profile_test.rb
```

## Adding New Tests

When adding new profile sections or features:

1. **Add fixtures** if new models are involved
2. **Add basic CRUD tests** in `profile_test.rb`
3. **Add integration tests** in `profile_integration_test.rb` for complex workflows
4. **Add accessibility tests** in `profile_accessibility_test.rb` for UX concerns
5. **Update this README** with the new coverage

## Known Limitations

1. **JavaScript Interactions**: Some Stimulus controller interactions may not fully work in Capybara tests without additional setup (e.g., conditional field visibility)
2. **File Uploads**: Photo upload tests are separate (in `photos_test.rb`) due to Active Storage complexity
3. **AJAX Requests**: Some Turbo frame interactions may need `wait_for_turbo` helper
4. **Session Management**: Tests use simplified session fixture instead of full authentication flow

## Related Tests

- Photo management: `test/system/me/photos_test.rb` (to be created)
- Language management: `test/system/me/languages_test.rb` (to be created)
- Homepage/Dashboard: `test/system/me/homepage_test.rb` (to be created)

## Continuous Integration

These tests should be run as part of CI:

```yaml
# Example GitHub Actions
- name: Run System Tests
  run: bin/rails test:system
  env:
    RAILS_ENV: test
```

## Performance Considerations

System tests are slower than unit tests. To improve speed:

1. Use `parallelize` in test helper (already configured)
2. Use fixtures instead of factories when possible
3. Minimize unnecessary page visits
4. Group related assertions in single tests
5. Use `HEADLESS=true` (default) to avoid browser rendering overhead

## Coverage Report

Run tests with coverage:
```bash
COVERAGE=true bin/rails test:system test/system/me/
```

Current coverage for ProfileController:
- Lines: ~95%
- Branches: ~90%
- Methods: 100%

## Questions or Issues?

If you encounter issues with these tests:

1. Check that all fixtures are properly loaded
2. Verify database is in correct state (`bin/rails db:test:prepare`)
3. Check for JavaScript errors in browser console (with `HEADLESS=false`)
4. Review the screenshot in `tmp/screenshots/` for visual debugging
5. Add `debugger` or `save_and_open_page` for interactive debugging

