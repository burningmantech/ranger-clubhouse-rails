# frozen_string_literal: true

require "test_helper"

class BmidExportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 7, 1, 12, 0, 0)
    BmidExport.delete_all
    @person = person(:active_ranger)
  end

  teardown do
    travel_back
  end

  test "person_ids round-trips as a JSON array, the format Laravel wrote" do
    export = BmidExport.create!(person: @person, filename: "ranger-bmids-test.csv",
                                person_ids: [3, 1, 2])

    assert_equal [3, 1, 2], export.reload.person_ids
    assert_equal "[3,1,2]", export.read_attribute_before_type_cast(:person_ids)
  end

  test "batch_info defaults to an empty string for the NOT NULL column" do
    export = BmidExport.create!(person: @person, filename: "ranger-bmids-test.csv",
                                person_ids: [1])

    assert_equal "", export.reload.batch_info
  end

  test "for_year scopes by the created_at year" do
    this_year = BmidExport.create!(person: @person, filename: "a.csv", person_ids: [1])
    BmidExport.create!(person: @person, filename: "b.csv", person_ids: [2],
                       created_at: Time.local(YEAR - 1, 8, 30))

    assert_equal [this_year.id], BmidExport.for_year(YEAR).pluck(:id)
  end
end
