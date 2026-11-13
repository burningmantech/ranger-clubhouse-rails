# frozen_string_literal: true

require "test_helper"

# Only the unassigned state has ever had a snapshot behind it, which is how the
# other two drifted into three different presentations of one idea.
class Vc::ApplicationsHelperTest < ActionView::TestCase
  include Vc::ApplicationsHelper
  include UiComponents::BadgeHelper

  setup do
    @viewer = person(:auditor_ranger)
    @other = person(:active_ranger)
    @application = prospective_application(:pending_qualified)
  end

  test "an application assigned to the viewer names them, not their callsign" do
    @application.assigned_person_id = @viewer.id

    assert_equal "Assigned to you.", application_assignment_note(@application, @viewer)
  end

  test "an application assigned to someone else names them" do
    @application.assigned_person_id = @other.id

    assert_equal "Assigned to #{@other.callsign}.", application_assignment_note(@application, @viewer)
  end

  # "unsigned" for most of this file's life. An application is assigned or not;
  # nobody signs one.
  test "an unassigned application says unassigned" do
    @application.assigned_person_id = nil

    assert_equal "Application is unassigned.", application_assignment_note(@application, @viewer)
  end

  # The hero description is one sentence in the panel's own style: no ink, no
  # weight, no size of its own.
  test "every state is plain text" do
    [@viewer.id, @other.id, nil].each do |assignee|
      @application.assigned_person_id = assignee

      assert_no_match(/</, application_assignment_note(@application, @viewer))
    end
  end

  # ui_badge has no info or neutral variant; asking for one fell back silently.
  test "the waiting statuses ask for a badge variant that exists" do
    html = application_status_badge(ProspectiveApplication::STATUS_PENDING)

    assert_includes html, "badge-secondary"
    assert_includes application_status_badge(ProspectiveApplication::STATUS_HANDLE_CHECK), "badge-secondary"
  end

  test "filter chips name each narrowing filter and widen just that one" do
    filter = Vc::ApplicationFilterForm.new(status: Vc::ApplicationFilterForm::GROUP_HELD, age: "young")

    chips = application_filter_chips(filter, [], 2026)

    assert_equal ["Status: On Hold", "Age: Is < 18"], chips.pluck(:label)
    status_url = CGI.unescape(chips.first[:url])
    assert_includes status_url, "filter[status]=all"
    assert_includes status_url, "filter[age]=young"
  end
end
