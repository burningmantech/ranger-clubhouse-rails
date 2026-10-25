# frozen_string_literal: true

require "ostruct"

# Per-position totals (shift count, duration, credits) for a set of timesheet
# entries, sorted by position title.
class PositionWorkSummary
  def self.execute(timesheets)
    timesheets.group_by { |sheet| sheet.position.title }.sort.map do |title, group|
      OpenStruct.new(
        title:,
        credits: group.sum(&:credits),
        duration: group.sum(&:duration),
        shifts: group.length,
        hours_counted: group.first.position.count_hours
      )
    end
  end
end
