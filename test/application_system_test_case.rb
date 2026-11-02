require "test_helper"
require "support/system_test_helpers"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  include SystemTestHelpers

  # The navbar binds its hotkeys for the client's platform
  # (NavbarHelper#kbd_modifier_filter), so every test starts on Linux, whatever
  # the host, and presses Ctrl. A test of the Mac chords calls
  # emulate_platform(:mac).
  setup { emulate_platform(:linux) }

  # The CI runner shares four cores among eight Chromes and eight servers, so
  # a toast's Stimulus controller can connect after Capybara's two seconds.
  Capybara.default_max_wait_time = 5 if ENV["CI"].present?

  # sign_in hands its session to ApplicationController.test_session, so mixed
  # controller/system runs stay signed in, and a class attribute outlives the
  # test. Left set, the next test's first visit renders signed in as this
  # test's person while the browser has no cookie yet; the layout's cable
  # stream is then refused, and turbo-rails' visit, which waits for it to
  # connect, fails that test at sign-in. So does every system test after it.
  teardown do
    ApplicationController.test_session = nil if ApplicationController.respond_to?(:test_session=)
  end
end
