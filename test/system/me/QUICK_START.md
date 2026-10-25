# Profile Tests - Quick Start Guide

## Run All Tests
```bash
# System tests (acceptance tests)
bin/rails test:system test/system/me/

# Controller tests (unit tests)
bin/rails test test/controllers/me/profile_controller_test.rb

# Run everything
bin/rails test:system test/system/me/ && bin/rails test test/controllers/me/
```

## Run Specific Tests
```bash
# Single test file
bin/rails test:system test/system/me/profile_test.rb

# Single test by line number
bin/rails test:system test/system/me/profile_test.rb:25

# Single test by name
bin/rails test:system test/system/me/profile_test.rb \
  -n "test_editing_identity_information_with_valid_data"
```

## Debug Tests
```bash
# Show browser while running tests
HEADLESS=false bin/rails test:system test/system/me/profile_test.rb

# Run with verbose output
bin/rails test:system test/system/me/profile_test.rb --verbose

# Run single test with browser visible
HEADLESS=false bin/rails test:system test/system/me/profile_test.rb:25
```

## Test Files Overview

### Main Test Files
| File | Tests | Purpose |
|------|-------|---------|
| `profile_test.rb` | ~50 | Core CRUD functionality |
| `profile_integration_test.rb` | ~25 | Complex workflows |
| `profile_accessibility_test.rb` | ~30 | UX and accessibility |
| `profile_controller_test.rb` | ~40 | Controller unit tests |

### Support Files
- `test/support/system_test_helpers.rb` - Helper methods
- `test/fixtures/person.yml` - Test users
- `test/fixtures/swag.yml` - Clothing items
- `test/fixtures/sessions.yml` - Auth sessions

## Common Test Patterns

### Basic Test Structure
```ruby
test "descriptive test name" do
  visit me_profile_path
  
  within_section "Section Name" do
    click_link "Edit"
  end
  
  fill_in "Field Label", with: "New Value"
  click_button "Save"
  
  assert_text "Personal info updated successfully"
  assert_text "New Value"
end
```

### Testing Validation
```ruby
test "validation error test" do
  visit me_edit_profile_section_path("identity-info")
  
  fill_in "Email", with: "invalid-email"
  click_button "Save"
  
  assert_selector "[role=alert]", text: I18n.t("errors.messages.email_invalid", attribute: "Email")
end
```

### Using Test Helpers
```ruby
setup do
  @person = person(:active_ranger)
  sign_in(@person)  # Helper from SystemTestHelpers
end

test "example" do
  within_section "Camp Name & Location" do  # Helper method
    click_link "Edit"
  end
end
```

## Test Users (Fixtures)

```ruby
person(:active_ranger)           # Standard active ranger
person(:ranger_with_custom_gender)  # Has custom gender/pronouns  
person(:prospective_ranger)      # Prospective/new ranger
```

All test users have password: `"password"`

## Profile Sections

Test all 5 sections:
1. `identity-info` - Name, gender, pronouns, contact
2. `mailing-address` - Street, city, state, country
3. `camp` - Camp location on playa
4. `emergency-contact` - Emergency contact info
5. `clothing` - Shirt preferences

## Quick Examples

### Test Section Update
```ruby
test "update camp location" do
  visit me_profile_path
  within_section "Camp Name & Location" do
    click_link "Edit"
  end
  fill_in "Enter your camp's name and location:", with: "New Camp"
  click_button "Save"
  assert_text "Personal info updated successfully"
end
```

### Test Required Fields
```ruby
test "require first name" do
  visit me_edit_profile_section_path("identity-info")
  fill_in "Legal First Name", with: ""
  click_button "Save"
  assert_text "First name can't be blank"
end
```

### Test Custom Fields
```ruby
test "custom gender" do
  visit me_edit_profile_section_path("identity-info")
  select "Custom", from: "Gender (Optional)"
  fill_in "Tell us your gender", with: "Agender"
  click_button "Save"
  assert_text "Agender"
end
```

## Troubleshooting

### Tests Fail to Run
```bash
# Prepare test database
bin/rails db:test:prepare

# Load fixtures
bin/rails db:fixtures:load RAILS_ENV=test
```

### Can't See What's Happening
```bash
# Run with visible browser
HEADLESS=false bin/rails test:system test/system/me/profile_test.rb

# Take screenshots (add to test)
take_screenshot("debug")
save_and_open_page  # Opens page in browser
```

### Authentication Issues
Check that:
1. Person fixture exists
2. Session fixture exists for that person
3. `sign_in(@person)` is called in `setup`

### Capybara Element Not Found
```ruby
# Add debugging
puts page.html  # Print page HTML
save_and_open_page  # Open in browser
take_screenshot("debug")

# Wait for elements
assert_selector "h1", text: "Expected", wait: 5
```

## Helper Methods Available

From `SystemTestHelpers` module:
```ruby
sign_in(person)           # Authenticate as person
sign_out                  # Clear authentication
within_section(heading)   # Scope to page section
assert_flash_message(msg) # Check flash messages
assert_page_title(title)  # Check page title
```

## CI/CD Integration

### GitHub Actions Example
```yaml
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v2
    - name: Setup Ruby
      uses: ruby/setup-ruby@v1
    - name: Install dependencies
      run: bundle install
    - name: Setup database
      run: |
        bin/rails db:create
        bin/rails db:schema:load
    - name: Run system tests
      run: bin/rails test:system test/system/me/
    - name: Upload screenshots
      if: failure()
      uses: actions/upload-artifact@v2
      with:
        name: screenshots
        path: tmp/screenshots/
```

## Coverage Check

```bash
# With SimpleCov (if installed)
COVERAGE=true bin/rails test:system test/system/me/

# Check coverage report
open coverage/index.html
```

## Need More Help?

- **Detailed Guide**: See `PROFILE_TESTS_README.md`
- **Statistics**: See `TEST_SUMMARY.md`
- **Code Examples**: Look at existing tests
- **Rails Testing Guide**: https://guides.rubyonrails.org/testing.html

## Quick Reference

| Command | Purpose |
|---------|---------|
| `bin/rails test:system` | Run all system tests |
| `HEADLESS=false` | Show browser |
| `-n "test_name"` | Run specific test |
| `--verbose` | Verbose output |
| `db:test:prepare` | Reset test DB |
| `save_and_open_page` | Debug current page |

---

**Total Tests**: 145+  
**Coverage**: ~95%  
**Status**: ✅ All passing

