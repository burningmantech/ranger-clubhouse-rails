# frozen_string_literal: true

require "ostruct"

# A person's on-playa volunteer history across all years: total hours by
# year, by position, and by position-per-year, plus the years before 2008
# (placeholder entries, tracked separately) and whether any entries were
# logged as an Echelon volunteer.
#
# Alpha, Deep Freeze, and any position with "Training" in its title
# (including Advanced Ranger Training) are excluded — this report only
# covers on-playa volunteering.
#
# Ported from the Ember WorkHistoryComponent's _loadWorkHistory.
class WorkHistoryReport
  def self.execute(person_id)
    rows = Timesheet.find_for_query(person_id:).reject { |row| excluded_position?(row.position) }
    current_rows, prior_rows = rows.partition { |row| row.on_duty.year >= 2008 }
    rows_by_year = current_rows.group_by { |row| row.on_duty.year }

    years_map = rows_by_year.transform_values { |group| group.map(&:position_id).uniq }
    PositionCredit.warm_bulk_year_cache(years_map) if years_map.any?

    positions = current_rows.group_by(&:position_id).map { |_id, group| build_position(group) }.sort_by(&:title)
    year_totals = rows_by_year.transform_values { |group| build_totals(group) }

    OpenStruct.new(
      years: rows_by_year.keys.sort,
      inaccurate_years: prior_rows.map { |row| row.on_duty.year }.uniq.sort,
      year_totals:,
      positions:,
      total_duration: current_rows.sum(&:duration),
      has_echelon_work: current_rows.any?(&:is_echelon)
    )
  end

  def self.build_position(group)
    years = group.group_by { |row| row.on_duty.year }.transform_values { |year_group| build_totals(year_group) }

    OpenStruct.new(
      id: group.first.position_id,
      title: group.first.position.title,
      duration: group.sum(&:duration),
      entries: group,
      years:
    )
  end
  private_class_method :build_position

  def self.build_totals(group)
    OpenStruct.new(entries: group, duration: group.sum(&:duration))
  end
  private_class_method :build_totals

  def self.excluded_position?(position)
    position.id == Position::ALPHA || position.id == Position::DEEP_FREEZE || position.title.include?("Training")
  end
  private_class_method :excluded_position?
end
