# frozen_string_literal: true

# Filter selects and chips for the Forced Shift Starts audit page.
module Timesheets::ForcedShiftStartHelper
  FILTER_CHIP_LABELS = {
    person_id: "Person",
    forced_by_id: "Forced By",
    position_id: "Position",
    blocker: "Blocked Reason"
  }.freeze

  # Every select offers only the values the year's forced starts actually hold,
  # so no single choice can return nothing. A combination still can -- this
  # person never forced past that blocker -- and the page says so rather than
  # drawing an empty table.
  #
  # No counts on the labels, unlike the single-filter sibling pages: with four
  # filters a count taken over the whole year would promise a roster the choice
  # does not deliver once another filter is set.
  def forced_shift_start_person_options(entries)
    forced_shift_start_options(entries) { |entry| [entry.person_id, entry.callsign] }
  end

  # A start whose audit log is gone names no forcer, and there is nothing to
  # filter on; those rows are reachable only by clearing this filter.
  def forced_shift_start_forced_by_options(entries)
    forced_shift_start_options(entries) do |entry|
      next if entry.forced_by_id.blank?

      [entry.forced_by_id, person_display_name(entry.forced_by, entry.forced_by_id)]
    end
  end

  def forced_shift_start_position_options(entries)
    forced_shift_start_options(entries) { |entry| [entry.position_id, entry.position_title] }
  end

  # The bare check name, without the per-row detail timesheet_blocker_label adds
  # -- "45 minutes early" belongs to one row, not to the choice that gathers
  # every early check-in.
  def forced_shift_start_blocker_options(entries)
    names = entries.flat_map(&:blocker_names).uniq
    labels = Person::TimesheetsHelper::TIMESHEET_BLOCKER_LABELS

    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      names.map { |name| [labels[name] || name, name] }.sort_by { |label, _name| label.downcase }
  end

  def forced_shift_start_filter_chips(filters, entries, year)
    active = active_filters(filters)
    display = ->(key, value) { forced_shift_start_filter_value_label(key, value, entries) }

    filter_chips(active, FILTER_CHIP_LABELS, value_label: display) do |remaining|
      timesheets_forced_shift_start_path(year:, **remaining)
    end
  end

  private

  # The chip says what the select said. Reading it back off the entries rather
  # than off a lookup table keeps the two from drifting, and an id that survived
  # known_filter is always present in them.
  def forced_shift_start_filter_value_label(key, value, entries)
    case key
    when :person_id then entries.find { |entry| entry.person_id.to_s == value }&.callsign
    when :position_id then entries.find { |entry| entry.position_id.to_s == value }&.position_title
    when :forced_by_id
      entry = entries.find { |candidate| candidate.forced_by_id.to_s == value }
      entry && person_display_name(entry.forced_by, entry.forced_by_id)
    when :blocker then Person::TimesheetsHelper::TIMESHEET_BLOCKER_LABELS[value] || value
    end || value
  end

  def forced_shift_start_options(entries)
    pairs = entries.filter_map { |entry| yield entry }.uniq

    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      pairs.sort_by { |_value, label| label.to_s.downcase }
           .map { |value, label| [label, value.to_s] }
  end
end
