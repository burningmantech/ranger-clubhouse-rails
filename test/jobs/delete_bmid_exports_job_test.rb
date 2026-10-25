# frozen_string_literal: true

require "test_helper"

class DeleteBmidExportsJobTest < ActiveSupport::TestCase
  setup do
    BmidExport.delete_all
    @person = person(:active_ranger)
  end

  test "perform removes every archive, whichever year it belongs to" do
    this_year = create_export
    older = create_export
    older.update_column(:created_at, 3.years.ago)

    DeleteBmidExportsJob.perform_now

    assert_not BmidExport.exists?(this_year.id)
    assert_not BmidExport.exists?(older.id)
  end

  test "deleting one year leaves the others alone" do
    kept = create_export
    older = create_export
    older.update_column(:created_at, Time.zone.local(Current.year - 2, 8, 1, 12, 0, 0))

    assert_equal 1, BmidExport.delete_all_for_year(Current.year - 2)

    assert BmidExport.exists?(kept.id)
    assert_not BmidExport.exists?(older.id)
  end

  private

  def create_export
    BmidExport.create!(person: @person, filename: "ranger-bmids-test.csv", person_ids: [@person.id])
  end
end
