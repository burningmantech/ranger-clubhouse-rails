# frozen_string_literal: true

# Shared authentication helper for integration tests
# This bypasses signed cookie verification by directly returning the test session
# stored in a class variable, which persists across request boundaries
module AuthenticationTestHelper
  extend ActiveSupport::Concern

  # Module to override authentication in ApplicationController
  module ControllerOverride
    def find_session_by_cookie
      # Return the session stored in the controller's class variable
      # This is set by sign_in_as and persists across requests within a test.
      # With none set, the real cookie: the prepend outlives the test that
      # made it, and a sign-in a later test drives itself (a system test's
      # passkey) must still count.
      self.class.test_session || super
    end
  end

  included do
    setup do
      setup_authentication_override
    end

    teardown do
      cleanup_authentication
    end
  end

  private

  def setup_authentication_override
    # Prepend the override module to ApplicationController (only affects test requests)
    unless ApplicationController.ancestors.include?(ControllerOverride)
      ApplicationController.prepend(ControllerOverride)
    end

    # Add class variable accessor for test session if not already defined
    unless ApplicationController.respond_to?(:test_session)
      ApplicationController.class_eval do
        cattr_accessor :test_session
      end
    end
  end

  def cleanup_authentication
    # Clean up the test session if it exists
    sign_out if @test_session
  end

  def sign_in_as(person)
    # Create or reuse a session for the person
    @test_session = person.sessions.first || person.sessions.create!(
      session_id: "test_session_#{person.id}_#{SecureRandom.hex(8)}",
      ip_address: "127.0.0.1",
      user_agent: "Test User Agent",
      person_id: person.id,
      data: ""
    )

    # Store in ApplicationController's class variable so it persists across requests
    # This will be picked up by our overridden find_session_by_cookie
    ApplicationController.test_session = @test_session
  end

  def sign_out
    # Clean up the test session
    @test_session&.destroy
    @test_session = nil

    # Clear the ApplicationController class variable
    ApplicationController.test_session = nil

    # Reset Current attributes (for good measure)
    Current.reset
  end
end
