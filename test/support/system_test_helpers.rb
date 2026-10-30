# frozen_string_literal: true

require "support/person_test_factory"

module SystemTestHelpers
  include PersonTestFactory

  # How ui_section draws a section and its title. Kept here so a change to the
  # component is a one-line change for every system test.
  SECTION_SELECTOR = ".box"
  SECTION_HEADING_SELECTOR = "[role=heading]"

  # The message shown after any profile section is saved.
  PROFILE_UPDATED_FLASH = "Profile updated."

  # Authentication helper for system tests
  # Signs in a person by setting up a session cookie
  def sign_in(person)
    # Visit login page first to establish the domain for cookies
    # We use the login page because it allows unauthenticated access
    visit root_path

    # Ensure person has a session
    session = person.sessions.first
    unless session
      session = person.sessions.create!(
        session_id: SecureRandom.hex(32),
        ip_address: "127.0.0.1",
        user_agent: "Test User Agent"
      )
    end

    # The first-sign-in tour runs on /me for anyone who has not taken it, and
    # its overlay takes the pointer from everything but the step it shows, so a
    # test that lands there could click nothing. Everyone signs in toured; the
    # tour's own test clears this again.
    person.update_column(:on_boarded_at, Time.current) if person.on_boarded_at.nil?

    # Integration tests override cookie lookup via ApplicationController.test_session.
    # Set the same hook here so mixed controller/system runs stay authenticated.
    ApplicationController.test_session = session if ApplicationController.respond_to?(:test_session=)

    # Sign the cookie value using Rails' message verifier (same as cookies.signed)
    # Rails uses "signed cookie" as the default purpose for signed cookies
    signed_value = Rails.application.message_verifier("signed cookie").generate(session.session_id)

    # Set up authentication by creating a signed session cookie
    cookies = Capybara.current_session.driver.browser.manage
    cookies.add_cookie(
      name: "session_id",
      value: signed_value,
      path: "/",
      httponly: true
    )
  end

  # Signs out the current user
  def sign_out
    Current.session&.destroy
    Current.session = nil
    ApplicationController.test_session = nil if ApplicationController.respond_to?(:test_session=)

    cookies = Capybara.current_session.driver.browser.manage
    cookies.delete_cookie("session_id")
  end

  # Poll a block until it returns truthy or Capybara's default wait elapses:
  # for what Capybara's matchers cannot wait on, a JS-set value or a row that
  # a fetch writes after the DOM has settled.
  def assert_eventually(message = "condition not met in time")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time
    loop do
      return if yield
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    flunk message
  end

  # Waits until a Stimulus controller has connected to the element. Controllers
  # load lazily, so a test that acts before one connects tests the page without it.
  def wait_for_controller(identifier, selector)
    page.document.synchronize do
      connected = page.evaluate_script(<<~JS)
        !!window.Stimulus?.getControllerForElementAndIdentifier(document.querySelector(#{selector.to_json}),
                                                               #{identifier.to_json})
      JS
      raise Capybara::ExpectationNotMet, "#{identifier} never connected" unless connected
    end
  end

  # Wait until the debounce the last keys started in an autocomplete has run out,
  # so that a search it was going to start has started. The timer is on the
  # page's own clock, set after those keys and for longer than the component's
  # 300ms default, so it cannot fire first.
  def wait_out_debounce
    page.execute_script(<<~JS)
      delete document.documentElement.dataset.debounceOver
      setTimeout(() => { document.documentElement.dataset.debounceOver = "true" }, 320)
    JS
    assert_selector "html[data-debounce-over='true']", visible: :all
  end

  # Headless Chrome will not shrink its window below about 500px, so the phone
  # is emulated through the devtools protocol instead. 375x812 is an iPhone X;
  # height: 667 is the SE, for a test that needs the fold higher up.
  def on_a_phone(height: 812)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: 375, height:, deviceScaleFactor: 1, mobile: false)
    yield
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  # Find a section by its heading and perform actions within it
  # Usage: within_section("Name & Contact") { click_link "Edit" }
  #
  # Sections come from ui_section, whose title is a heading element rather than
  # an h3-h6 tag, inside a .box container.
  def within_section(heading, &block)
    section = find(SECTION_HEADING_SELECTOR, text: heading).ancestor(SECTION_SELECTOR)
    within(section, &block)
  end

  # Answers yes to the confirm dialog (ModalHelper#confirm_modal_dialog). One
  # press, with no waiting first: the dialog is wired before it is shown, and
  # pressing it this way is also the check that it stays so.
  def accept_confirm_dialog
    find("dialog[open] #turbo-confirm-button").click
  end

  # Assert that a flash message is displayed
  def assert_flash_message(message, type: :success)
    flash_class = case type
                  when :success then ".alert-success"
                  when :error then ".alert-error"
                  when :warning then ".alert-warning"
                  when :info then ".alert-info"
                  else ".alert"
                  end

    assert_selector flash_class, text: message
  end

  # Assert that form validation error messages are displayed
  def assert_validation_errors(*error_messages)
    error_messages.each do |error_message|
      assert_selector ".invalid-feedback, .alert-error, .error-message", text: error_message
    end
  end

  # Fill in a Bootstrap form field by label
  # Handles both regular inputs and custom components
  def fill_in_bootstrap_field(label, with:)
    # Try to find by label first
    begin
      fill_in label, with: with
    rescue Capybara::ElementNotFound
      # Try to find by placeholder
      fill_in placeholder: label, with: with
    end
  end

  # Select from a Bootstrap select by label
  def select_from_bootstrap(option, from:)
    select option, from: from
  end

  # Wait for Turbo to finish loading
  def wait_for_turbo
    # Wait for Turbo to not be loading
    assert_no_selector "[data-turbo-frame].turbo-frame-loading", wait: 5
  end

  # Check if user is on a specific page by checking the page title or heading
  def assert_page_title(title)
    assert_selector "h1, h2, title", text: title
  end

  # Take a screenshot with a descriptive name (useful for debugging)
  def take_debug_screenshot(name = "debug")
    timestamp = Current.time.strftime("%Y%m%d_%H%M%S")
    save_screenshot("tmp/screenshots/#{name}_#{timestamp}.png")
  end

  # Assert that a specific section is visible on the page
  def assert_section_visible(heading)
    assert_selector SECTION_HEADING_SELECTOR, text: heading, visible: true
  end

  # Assert that a specific section is not visible on the page
  def assert_section_not_visible(heading)
    assert_no_selector SECTION_HEADING_SELECTOR, text: heading, visible: true
  end

  # Verify that edit links are present for profile sections
  def assert_edit_link_present(section_id)
    assert_link "Edit", href: me_edit_profile_section_path(section_id)
  end

  # Helper to bypass HTML5 form validation for testing server-side validation.
  # On the form rather than on its fields, so that it covers a field that is not
  # an input: the rich text editor checks `required` itself.
  def bypass_html5_validation
    page.execute_script("document.querySelectorAll('form').forEach(form => { form.noValidate = true })")
  end

  # Assert that a form field has a specific data attribute (useful for Stimulus controllers)
  def assert_field_has_controller(field_name, controller_name)
    field = find_field(field_name)
    assert field["data-controller"]&.include?(controller_name),
           "Expected field #{field_name} to have controller #{controller_name}"
  end

  # Assert that the current user is redirected to login
  def assert_requires_authentication
    assert_current_path root_path
  end
end
