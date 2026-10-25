# frozen_string_literal: true

require "test_helper"

# where_year backs every for_year scope, so its boundaries are load-bearing
# across the app. See config/initializers/active_record_extensions.rb.
class WhereYearTest < ActiveSupport::TestCase
  setup { @person = person(:active_ranger) }

  test "selects the year the value is stored under, not the Time.zone year" do
    # Datetimes are stored as machine-local wall clock while Time.zone is
    # Phoenix. A Time.zone-anchored window would start an hour early and pull
    # this 23:30 record into 2025.
    log = logged_at(Time.local(2024, 12, 31, 23, 30))

    assert_includes for_year(2024), log
    assert_not_includes for_year(2025), log
  end

  test "includes the first and last instant of the year and excludes its neighbours" do
    first = logged_at(Time.local(2024, 1, 1, 0, 0))
    last = logged_at(Time.local(2024, 12, 31, 23, 59, 59))
    before = logged_at(Time.local(2023, 12, 31, 23, 59, 59))
    after = logged_at(Time.local(2025, 1, 1, 0, 0))

    assert_equal [first, last].sort, for_year(2024).sort
    assert_not_includes for_year(2024), before
    assert_not_includes for_year(2024), after
  end

  # The whole point of the range form: MariaDB cannot index YEAR(col).
  test "builds a sargable range rather than a function on the column" do
    sql = ActionLog.all.where_year("created_at", 2024).to_sql

    assert_no_match(/YEAR\s*\(/i, sql)
    assert_match(/created_at >= '2024-01-01 00:00:00'/, sql)
    assert_match(/created_at < '2025-01-01 00:00:00'/, sql)
  end

  test "where_years runs from the first instant of the first year to the last of the last" do
    first = logged_at(Time.local(2023, 1, 1, 0, 0))
    last = logged_at(Time.local(2024, 12, 31, 23, 59, 59))
    logged_at(Time.local(2022, 12, 31, 23, 59, 59))
    logged_at(Time.local(2025, 1, 1, 0, 0))

    span = ActionLog.where(event: "test-where-year").where_years("created_at", 2023, 2024).to_a

    assert_equal [first, last].sort, span.sort
  end

  test "accepts a table-qualified column" do
    log = logged_at(Time.local(2024, 6, 1, 12, 0))

    assert_includes ActionLog.all.where_year("action_logs.created_at", 2024), log
  end

  private

  def logged_at(time)
    ActionLog.create!(person_id: @person.id, event: "test-where-year",
                      message: "", created_at: time)
  end

  def for_year(year)
    ActionLog.where(event: "test-where-year").where_year("created_at", year).to_a
  end
end
