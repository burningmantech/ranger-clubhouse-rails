# frozen_string_literal: true

require "test_helper"

class ThankYouCardsReportTest < ActiveSupport::TestCase
  YEAR = 2023

  def shift_for(person, year: YEAR)
    Timesheet.create!(person:, position: positions(:ood_position),
                      on_duty: DateTime.new(year, 8, 28, 10, 0, 0), additional_notes: "test shift")
    person
  end

  # Borrows a fixture for each status, since most of them have no fixture of
  # their own and an untested status is one the report could silently mail.
  def someone_with(status)
    person(:plate_collision_ranger).tap do |borrowed|
      borrowed.update_columns(status:)
      shift_for(borrowed)
    end
  end

  test "includes a person who rangered that year" do
    assert_includes ThankYouCardsReport.execute(YEAR).map(&:id), person(:active_ranger).id
  end

  test "counts a person once no matter how many shifts they walked" do
    ranger = person(:active_ranger)
    shift_for(ranger)

    ids = ThankYouCardsReport.execute(YEAR).map(&:id)

    assert_equal 1, ids.count(ranger.id)
  end

  test "leaves out every status we never mail" do
    ThankYouCardsReport::ALWAYS_SKIPPED_STATUSES.each do |status|
      borrowed = someone_with(status)

      assert_not_includes ThankYouCardsReport.execute(YEAR).map(&:id), borrowed.id,
                          "expected #{status} to be left off the list"
    end
  end

  test "leaves out the optional statuses until they are asked for" do
    ThankYouCardsReport::OPTIONAL_STATUSES.each do |status|
      borrowed = someone_with(status)

      assert_not_includes ThankYouCardsReport.execute(YEAR).map(&:id), borrowed.id,
                          "expected #{status} to be left off by default"
      assert_includes ThankYouCardsReport.execute(YEAR, include_statuses: [status]).map(&:id), borrowed.id,
                      "expected #{status} to come back when asked for"
    end
  end

  test "asking for one optional status does not admit the rest" do
    borrowed = someone_with(Person::DECEASED)

    ids = ThankYouCardsReport.execute(YEAR, include_statuses: [Person::RESIGNED]).map(&:id)

    assert_not_includes ids, borrowed.id
  end

  test "ignores a year the person did not ranger" do
    assert_not_includes ThankYouCardsReport.execute(2022).map(&:id), person(:active_ranger).id
  end

  test "sorted by callsign" do
    callsigns = ThankYouCardsReport.execute(YEAR).map(&:callsign)

    assert_equal callsigns.sort_by(&:downcase), callsigns
  end

  test "reads every column the page and the export need" do
    ranger = ThankYouCardsReport.execute(YEAR).first

    ThankYouCardsReport::COLUMNS.each do |column|
      assert_nothing_raised { ranger.public_send(column) }
    end
  end
end
