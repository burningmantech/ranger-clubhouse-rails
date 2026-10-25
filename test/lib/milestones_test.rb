# frozen_string_literal: true

require "test_helper"

class MilestonesTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # Regression: this branch called the view-only `setting` helper, raising
  # NameError whenever an active person had worked a TS Mentor shift during
  # the event period.
  test "surfaces the TS mentor survey url when the person worked a mentor shift during the event" do
    person = person(:active_ranger)

    mentor = Position.create!(id: Position::TROUBLESHOOTER_MENTOR, title: "Troubleshooter Mentor")
    Timesheet.create!(
      person:,
      position: mentor,
      on_duty: Time.zone.local(2026, 8, 31, 10, 0, 0),
      off_duty: Time.zone.local(2026, 8, 31, 16, 0, 0),
      review_status: "verified",
      additional_notes: "test shift"
    )
    Setting.find_or_create_by(name: Setting::TROUBLESHOOTER_MENTOR_SURVEY_URL).update!(value: "https://example.com/ts-survey")

    milestones = travel_to Time.zone.local(2026, 9, 1, 12, 0, 0) do
      Milestones.build_for_person(person)
    end

    assert milestones.ts_mentor_worked
    assert_equal "https://example.com/ts-survey", milestones.ts_mentor_survey_url
  end
end
