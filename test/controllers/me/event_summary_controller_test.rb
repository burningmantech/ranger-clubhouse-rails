# frozen_string_literal: true

require "test_helper"

class Me::EventSummaryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  test "index requires authentication" do
    sign_out

    get me_event_summary_url
    assert_redirected_to root_path
  end

  # Note: Additional tests for event summary require fixture data for EventDate
  # which defines when the event period starts/ends. Without this data, the
  # controller may fail. The authentication test covers the basic routing.
end
