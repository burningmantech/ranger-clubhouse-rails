# frozen_string_literal: true

require "test_helper"

# What a sender is told about the broadcast channels that deliver to no one.
class RbsSandboxTest < ActiveSupport::TestCase
  include SesTestHelper

  setup do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
  end

  test "emails held back where sending to Rangers is not switched on are named" do
    assert_not_includes RbsSandbox.on, "emails"

    with_rangers_emailed(false) { assert_includes RbsSandbox.on, "emails" }
  end

  test "the email sandbox is named as before" do
    sandbox_on(Setting::BROADCAST_MAIL_SANDBOX)

    assert_includes RbsSandbox.on, "emails"
  end

  test "a test address is named, and email is not listed as held" do
    set_test_address("test+?@example.com")

    # Off, so that only the test address keeps email off the list.
    with_rangers_emailed(false) do
      assert_equal "test+?@example.com", RbsSandbox.email_test_address
      assert_not_includes RbsSandbox.on, "emails"
    end
  end

  test "with the sandbox on, the sandbox wins over a test address" do
    sandbox_on(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")

    assert_includes RbsSandbox.on, "emails"
    assert_nil RbsSandbox.email_test_address
  end

  # The settings form refuses such a value, and the send records each email
  # failed with an error log; the notice says nothing about it.
  test "a test address that cannot be used names neither the address nor email as held" do
    set_test_address("test@example.com")

    assert_nil RbsSandbox.email_test_address
    assert_not_includes RbsSandbox.on, "emails"
  end

  test "no test address is named while none is set" do
    assert_nil RbsSandbox.email_test_address
  end
end
