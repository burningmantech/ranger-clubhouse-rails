# frozen_string_literal: true

require "test_helper"

class SignupBlockersPartialTest < ActionView::TestCase
  include ApplicationHelper
  include UiComponents::NoticeBoxHelper

  Permission = Struct.new(:requirements, :training_signups_allowed)

  test "training-only warning renders the accent card title once" do
    permission = Permission.new([], false)

    render partial: "common/scheduling/signup_blockers", locals: { permission: }

    assert_select "article span", text: "Waiting for Course Completion", count: 1
  end
end
