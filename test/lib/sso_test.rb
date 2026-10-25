# frozen_string_literal: true

require "test_helper"

# The mode switch, and what each side needs from the environment.
class SsoTest < ActiveSupport::TestCase
  include SsoTestHelper

  # The mode is fixed at the server for now. The variable is not read, so
  # nothing set, a client, or a value that means nothing all leave it there.
  test "every Clubhouse is the server, whatever the variable says" do
    [nil, Sso::SERVER, Sso::CLIENT, "both"].each do |mode|
      with_sso_mode(mode) do
        assert_equal Sso::SERVER, Sso.mode
        assert_not Sso.client?
        assert_nothing_raised { Sso.validate! }
      end
    end
  end

  test "client settings are read with the space around them taken off" do
    with_sso_mode(Sso::CLIENT, client_id: " clubhouse3 ") do
      assert_equal "clubhouse3", Sso.client_settings.client_id
      assert_equal "clubhouse.example.org", Sso.server_host
    end
  end

  test "a sign-in address that cannot be read leaves the host blank rather than raising" do
    with_sso_mode(Sso::CLIENT, authorize_url: "not a url") do
      assert_nil Sso.server_host
    end
  end
end
