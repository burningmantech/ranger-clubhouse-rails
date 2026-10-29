# frozen_string_literal: true

require "test_helper"

# An ART group's times are its shift's, a wall clock in the shift's own zone,
# or -- for sign-ins matched to no shift -- a sign-in, on the app's clock.
# January, when Pacific runs an hour behind Phoenix, tells the two apart.
class Training::MentoringHelperTest < ActionView::TestCase
  tests Training::MentoringHelper
  include DateTimeHelper

  def group(slot:, begins:)
    ArtMentoring::Shifts::Group.new(key: "k", slot:, begins:, mentee_entries: [], on_shift_entries: [],
                                    mentor_entries: [], walks: {}, promotable: Set.new)
  end

  test "a matched group's shift and window are on the shift's own clock" do
    begins = Time.zone.local(2026, 1, 15, 7, 0)
    matched = group(slot: Slot.new(begins:, ends: begins + 6.hours, timezone: "America/Los_Angeles"), begins:)

    assert_includes art_mentoring_shift_label(matched), %(data-utc="2026-01-15T15:00:00Z") # 07:00 PST
    assert_includes art_mentoring_window(matched), %(data-utc="2026-01-15T16:00:00Z") # 08:00 PST
  end

  test "an unmatched group's window runs from its sign-in on the app's clock" do
    unmatched = group(slot: nil, begins: Time.zone.local(2026, 1, 15, 7, 0))

    assert_includes art_mentoring_window(unmatched), %(data-utc="2026-01-15T15:00:00Z") # 08:00 MST
  end
end
