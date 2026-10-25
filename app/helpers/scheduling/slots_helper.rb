# frozen_string_literal: true

module Scheduling::SlotsHelper
  # Timezone choices offered by the slot form. The Ember constant was not
  # ported; this is the curated equivalent.
  TIMEZONES = [
    "America/Los_Angeles",
    "America/Denver",
    "America/Phoenix",
    "America/Chicago",
    "America/New_York",
    "America/Anchorage",
    "Pacific/Honolulu",
    "UTC"
  ].freeze

  # Prepends the slot's stored timezone when it is not in the curated list so
  # editing never silently changes it.
  def slot_timezone_choices(slot)
    if slot.timezone.blank? || TIMEZONES.include?(slot.timezone)
      TIMEZONES
    else
      [slot.timezone, *TIMEZONES]
    end
  end

  def slot_status_badge(slot)
    if slot.active
      ui_badge "Active", :success, icon: "circle-check", icon_type: :solid
    else
      ui_badge "Inactive", :secondary, icon: "circle-pause", icon_type: :solid
    end
  end

  # Position select choices for the slot form, grouped into Active/Inactive
  # optgroups (mirrors the Ember slot form).
  def slot_position_choices(positions)
    active, inactive = positions.partition(&:active)

    [
      ["Active", active.map { |p| [p.title, p.id] }],
      ["Inactive", inactive.map { |p| [p.title, p.id] }]
    ].reject { |_label, options| options.empty? }
  end

  SLOT_FILTER_CHIP_LABELS = { day: "Day", active: "Status", description: "Description" }.freeze

  # One filter_bar chip per active position-page filter; each URL drops that
  # filter and keeps the rest.
  def slot_filter_chips(position, year)
    active = params.permit(:day, :active, :description).to_h.symbolize_keys.compact_blank

    filter_chips(active, SLOT_FILTER_CHIP_LABELS, value_label: method(:slot_filter_value_label)) do |remaining|
      scheduling_slots_position_path(position.id, remaining.merge(year:))
    end
  end

  SLOT_COPY_FILTER_CHIP_LABELS =
    { description: "Description", date: "Date", time: "Time", datetime: "Date/Time" }.freeze

  # One filter_bar chip per active copy-page filter; each URL drops that filter
  # and keeps the rest (plus the source position and year).
  def slot_copy_filter_chips(source_position_id, year, filter)
    active = filter.symbolize_keys

    filter_chips(active, SLOT_COPY_FILTER_CHIP_LABELS, value_label: method(:slot_filter_value_label)) do |remaining|
      scheduling_new_slot_copy_path(position_id: source_position_id, year:, filter: remaining.presence)
    end
  end

  SLOT_BULK_EDIT_FILTER_CHIP_LABELS = SLOT_COPY_FILTER_CHIP_LABELS.merge(active: "Status").freeze

  # One filter_bar chip per active bulk-edit filter; each URL drops that filter
  # and keeps the rest (plus the year).
  def slot_bulk_edit_filter_chips(position, year, filter)
    active = filter.symbolize_keys

    filter_chips(active, SLOT_BULK_EDIT_FILTER_CHIP_LABELS, value_label: method(:slot_filter_value_label)) do |remaining|
      scheduling_new_slot_bulk_edit_path(position.id, year:, filter: remaining.presence)
    end
  end

  # Trainer/parent link select choices: "Position - description - Wed Aug 26 @ 06:45".
  # Times are the stored wall-clock values, matching the Ember option labels.
  def slot_link_choices(slots)
    slots.map do |slot|
      ["#{slot.position_title} - #{slot.description} - #{slot.begins.strftime(DateTimeHelper::MONTH_DAY_TIME)}",
       slot.id]
    end
  end

  private

  # Human label for a filter chip's value. Unparsable dates fall back to the raw
  # value so a hand-edited URL still renders a removable chip.
  def slot_filter_value_label(key, value)
    case key
    when :day, :date
      wday_month_day_format(Date.iso8601(value))
    when :datetime
      value.to_time.strftime(DateTimeHelper::MONTH_DAY_TIME)
    when :active
      value == "active" ? "Active" : "Inactive"
    else # :description, :time
      value
    end
  rescue ArgumentError
    value
  end
end
