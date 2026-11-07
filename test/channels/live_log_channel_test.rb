# frozen_string_literal: true

require "test_helper"

# A client may subscribe to any channel class by name, and call any public
# method of its subscription as an action, so the shared base has to refuse on
# its own and the live channels must offer no action at all.
class LiveLogChannelTest < ActionCable::Channel::TestCase
  include TimesheetAdminTestHelper

  teardown do
    Current.reset
  end

  test "the base channel on its own refuses everyone, an Admin included" do
    admin = person(:auditor_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(admin, Role::ADMIN)
    stub_connection current_user: admin

    subscribe

    assert_predicate subscription, :rejected?
  end

  # A public subscribed would be one: calling it again resets the window and
  # replaces the lock while a tick holds the old one.
  test "no live channel takes an action from its client" do
    assert_empty LiveLogChannel.action_methods
    assert_empty RequestLogLiveChannel.action_methods
    assert_empty ActionLogLiveChannel.action_methods
  end
end
