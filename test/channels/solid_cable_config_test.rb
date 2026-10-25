# frozen_string_literal: true

require "test_helper"

# Solid Cable reads its durations with its own parser, which splits on "." and
# calls the last piece as a method: a bare number (polling_interval: 5) raises
# in the listener thread, which dies, and nothing is ever delivered. Tests run
# the test adapter and never start that thread, so only this sees it.
class SolidCableConfigTest < ActiveSupport::TestCase
  test "every Solid Cable environment's durations are ones Solid Cable can read" do
    %w[development production].each do |env|
      config = Rails.application.config_for(:cable, env:)
      assert_equal "solid_cable", config[:adapter], env

      %i[polling_interval message_retention].each do |key|
        duration = SolidCable.send(:parse_duration, config[key], default: nil)
        assert_kind_of ActiveSupport::Duration, duration, "#{env} #{key}: #{config[key].inspect}"
      end
    end
  end
end
