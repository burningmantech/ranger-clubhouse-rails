# frozen_string_literal: true

require "test_helper"

class ShinyPennyReportTest < ActiveSupport::TestCase
  # Clear of the 2025/2026 fixture data.
  YEAR = 2031

  setup do
    @alpha = Position.create!(id: Position::ALPHA, title: "Alpha")
    @penny = person(:prospective_ranger) # ProspectiveNewbie
    @second = person(:alpha_ranger)      # AlphaNewbie
  end

  def status_change(person, new_status, at)
    PersonStatus.create!(person:, old_status: Person::PROSPECTIVE, new_status:,
                         created_at: Time.zone.parse(at))
  end

  def walk_alpha(person, at)
    Timesheet.create!(person:, position: @alpha, on_duty: Time.zone.parse(at),
                      additional_notes: "test shift")
  end

  test "reports people who became active and walked an alpha shift, sorted by callsign" do
    status_change(@penny, Person::ACTIVE, "2031-09-05 12:00")
    walk_alpha(@penny, "2031-08-28 18:00")
    status_change(@second, Person::ACTIVE, "2031-09-06 12:00")
    walk_alpha(@second, "2031-08-29 18:00")

    assert_equal %w[AlphaNewbie ProspectiveNewbie], ShinyPennyReport.execute(YEAR).map(&:callsign)
  end

  test "excludes an accidental mint whose status moved off active later in the year" do
    status_change(@penny, Person::ACTIVE, "2031-09-05 12:00")
    status_change(@penny, Person::PAST_PROSPECTIVE, "2031-09-06 12:00")
    walk_alpha(@penny, "2031-08-28 18:00")

    assert_empty ShinyPennyReport.execute(YEAR)
  end

  test "excludes someone who became active without walking an alpha shift" do
    status_change(@penny, Person::ACTIVE, "2031-09-05 12:00")

    assert_empty ShinyPennyReport.execute(YEAR)
  end

  test "ignores an alpha shift walked in another year" do
    status_change(@penny, Person::ACTIVE, "2031-09-05 12:00")
    walk_alpha(@penny, "2030-08-28 18:00")

    assert_empty ShinyPennyReport.execute(YEAR)
  end

  test "ignores a status change made in another year" do
    status_change(@penny, Person::ACTIVE, "2030-09-05 12:00")
    walk_alpha(@penny, "2031-08-28 18:00")

    assert_empty ShinyPennyReport.execute(YEAR)
  end
end
