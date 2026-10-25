# frozen_string_literal: true

require "test_helper"

# The rule's table of addresses is in test/lib/rbs_test.rb, which asks it
# through Rbs.sendable_address?.
class EmailAddressesTest < ActiveSupport::TestCase
  test "no address is not a sendable one, and asking does not raise" do
    assert_equal false, EmailAddresses.sendable?(nil)
  end
end
