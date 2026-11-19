# frozen_string_literal: true

# Until the on-site cleanup existed, an admin cleared the on-site flag in bulk
# months after each event, so thousands of off-site marks carry a date in
# January, February or November that says when the reset was run, not when
# anyone left. This re-dates each of them the way the cleanup would have: at the
# person's last shift sign-out or asset return during that stay, with the
# reason "automatic".
#
# A reset mark is an off-site mark that closes a stay (it directly follows an
# on-site mark) and is dated more than 1 month and at most 7 months after Labor
# Day of the year the stay began. The window is read from the on-site mark's
# year because "months since the latest Labor Day" would catch every ordinary
# mark made at the next event: August 30 is eleven months past the last one.
#
# A mark with no sign-out or asset return between the two marks is left exactly
# as it is. Its date is the only one on record, and a new date outside the stay
# would put the off-site mark ahead of the on-site mark it closes.
class RedateBulkOffSiteMarks < ActiveRecord::Migration[8.1]
  ON_SITE = "on-site"
  OFF_SITE = "off-site"
  MANUAL = "manual"
  AUTOMATIC = "automatic"

  # The tables as they are today, whatever the app models become.
  class MigrationPersonOnSite < ActiveRecord::Base
    self.table_name = "person_on_site"
  end

  class MigrationTimesheet < ActiveRecord::Base
    self.table_name = "timesheet"
  end

  class MigrationPersonAsset < ActiveRecord::Base
    self.table_name = "person_asset"
  end

  def up
    # AddReasonToPersonOnSite may have run a moment ago in this same process.
    MigrationPersonOnSite.reset_column_information

    redated = undated = 0
    say_with_time "Re-dating the yearly resets' off-site marks" do
      redated, undated = redate_marks
      redated
    end
    say "#{redated} re-dated; #{undated} left as they were, with no sign-out or asset return in the stay"
  end

  def down
    # Nothing to undo: the old dates are not kept. They recorded when an admin
    # ran a reset, not when anyone left. Running up again changes nothing.
  end

  private

  # @return [Array(Integer, Integer)] marks re-dated, marks left alone
  def redate_marks
    redated = undated = 0

    reset_marks.group_by { it[:year] }.each do |year, marks|
      activity = activity_in(year, marks.map { it[:person_id] }.uniq)

      marks.each do |mark|
        left_at = activity.fetch(mark[:person_id], [])
                          .select { it > mark[:opened_at] && it < mark[:closed_at] }.max
        if left_at
          MigrationPersonOnSite.where(id: mark[:id]).update_all(created_at: left_at, reason: AUTOMATIC)
          redated += 1
        else
          undated += 1
        end
      end
    end

    [redated, undated]
  end

  # Every off-site mark a yearly reset made, with the stay it closed. A mark
  # already automatic is skipped, so a second run finds nothing to do.
  def reset_marks
    MigrationPersonOnSite.order(:person_id, :created_at, :id)
                         .pluck(:id, :person_id, :action, :reason, :created_at)
                         .each_cons(2).filter_map do |opened, closed|
      id, person_id, action, reason, closed_at = closed
      next unless opened[1] == person_id && opened[2] == ON_SITE && action == OFF_SITE && reason == MANUAL

      opened_at = opened[4]
      next unless reset_window?(closed_at.to_date, opened_at.year)

      { id:, person_id:, year: opened_at.year, opened_at:, closed_at: }
    end
  end

  # More than 1 month and at most 7 months after that year's Labor Day, the
  # first Monday of September: early October to early April.
  def reset_window?(date, year)
    labor_day = Date.new(year, 9, 1)
    labor_day += 1 until labor_day.monday?

    date > (labor_day >> 1) && date <= (labor_day >> 7)
  end

  # {person_id => [every sign-out and asset return of theirs that year]}
  def activity_in(year, person_ids)
    signed_out = MigrationTimesheet.where(person_id: person_ids).where_year("on_duty", year)
                                   .where.not(off_duty: nil).pluck(:person_id, :off_duty)
    returned = MigrationPersonAsset.where(person_id: person_ids).where_year("checked_out", year)
                                   .where.not(checked_in: nil).pluck(:person_id, :checked_in)

    (signed_out + returned).each_with_object({}) { |(person_id, at), times| (times[person_id] ||= []) << at }
  end
end
