# frozen_string_literal: true

require "test_helper"

# Only the unassigned state has ever had a snapshot behind it, which is how the
# other two drifted into three different presentations of one idea.
class Vc::ApplicationsHelperTest < ActionView::TestCase
  include Vc::ApplicationsHelper

  setup do
    @viewer = person(:auditor_ranger)
    @other = person(:active_ranger)
    @application = prospective_application(:pending_qualified)
  end

  test "an application assigned to the viewer names them, not their callsign" do
    @application.assigned_person_id = @viewer.id

    html = application_assignment_note(@application, @viewer)

    assert_includes html, "Assigned to you"
    assert_includes html, "text-success"
  end

  test "an application assigned to someone else names them" do
    @application.assigned_person_id = @other.id

    html = application_assignment_note(@application, @viewer)

    assert_includes html, "Assigned to #{@other.callsign}"
    assert_includes html, "text-warning"
  end

  # "unsigned" for most of this file's life. An application is assigned or not;
  # nobody signs one.
  test "an unassigned application says unassigned" do
    @application.assigned_person_id = nil

    html = application_assignment_note(@application, @viewer)

    assert_includes html, "Application is unassigned"
    assert_includes html, "text-stone-muted"
  end

  # All three are one sentence in one shape; only the ink changes.
  test "every state is the same span but for its ink" do
    shapes = [@viewer.id, @other.id, nil].map do |assignee|
      @application.assigned_person_id = assignee
      application_assignment_note(@application, @viewer)[/class="([^"]*)"/, 1].split - %w[text-success text-warning text-stone-muted]
    end

    assert_equal [%w[font-semibold text-lg]] * 3, shapes
  end
end
