# frozen_string_literal: true

# Lets a test assert what the app returns for an *unhandled* exception.
#
# The test environment runs `show_exceptions = :rescuable`, so a bare
# StandardError is re-raised out of the request rather than becoming a
# response -- which is what you want almost everywhere, since it puts the real
# backtrace in front of you. Production runs `:all`, where an unhandled error
# is a 500 page, so a test asserting that behavior has to opt in.
#
# Until 2026-08-03 these tests passed without opting in, by accident: the
# better_errors gem inserts its middleware whenever
# `consider_all_requests_local` is set, which config/environments/test.rb does,
# so it was catching every exception in the test stack and rendering a 500.
# Dropping the gem took the accident with it.
module ExceptionRenderingTestHelper
  def with_exceptions_rendered
    key = "action_dispatch.show_exceptions"
    original = Rails.application.env_config[key]
    Rails.application.env_config[key] = :all
    yield
  ensure
    Rails.application.env_config[key] = original
  end
end
