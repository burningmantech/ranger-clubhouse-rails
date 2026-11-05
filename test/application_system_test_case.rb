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
end
