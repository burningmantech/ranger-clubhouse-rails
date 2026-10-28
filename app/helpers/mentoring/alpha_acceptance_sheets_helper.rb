# frozen_string_literal: true

# Presentation for /mentoring/alpha-acceptance-sheets: the two filters, and the
# shift and training labels shared by the picker table and the printed form.
#
# The filter values themselves come from AlphaAcceptanceSheets, not from the
# controller: a helper that names a controller constant at load time makes the
# two autoloads wait on each other, and the controller loses its own class
# macros.
module Mentoring::AlphaAcceptanceSheetsHelper
  FILTER_LABELS = { shift: "Mentor Shift", issues: "Issues" }.freeze

  ISSUE_FILTER_LABELS = {
    AlphaAcceptanceSheets::WITHOUT_ISSUES => "Ready to print",
    AlphaAcceptanceSheets::WITH_ISSUES => "Needs attention"
  }.freeze

  # Upstream's filter options: All, then Alphas signed up to nothing, then one
  # entry per Alpha shift.
  def alpha_acceptance_shift_options(slots)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
     ["No mentor shift", AlphaAcceptanceSheets::NO_SHIFT]] +
      slots.map { |slot| [alpha_acceptance_slot_label(slot), slot.id.to_s] }
  end

  def alpha_acceptance_issues_options
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      ISSUE_FILTER_LABELS.map { |value, label| [label, value] }
  end

  def alpha_acceptance_filter_chips(filter_params, slots)
    active = UiComponents::FilterBarHelper.active_filters(filter_params)

    filter_chips(active, FILTER_LABELS,
                 value_label: ->(key, value) { alpha_acceptance_filter_value(key, value, slots) }) do |remaining|
      mentoring_alpha_acceptance_sheets_path(remaining)
    end
  end

  # A shift's own label. slot.begins is already local wall-clock, so it is
  # formatted directly -- passing it through a timezone-aware formatter would
  # shift the hour a mentor reads off the page.
  def alpha_acceptance_slot_label(slot)
    label = slot.begins.strftime(DateTimeHelper::MONTH_DAY_TIME)
    label += "<br>#{slot.description}" if slot.description.present?
    label.html_safe
  end

  # A training sign-up as the picker table lists it: when, then where.
  # safe_join, not Array#join: datetime_format returns marked-safe markup (it
  # wraps the time in a span carrying the timezone), and joining it into a
  # plain String would strip that mark and print the tags as text.
  def alpha_acceptance_training_label(training)
    parts = [datetime_format(training.slot_begins, tz: training.slot_tz)]
    parts << training.slot_description if training.slot_description.present?
    safe_join(parts, "<br>".html_safe)
  end

  private

  def alpha_acceptance_filter_value(key, value, slots)
    return ISSUE_FILTER_LABELS.fetch(value, value) if key == :issues
    return "None" if value == AlphaAcceptanceSheets::NO_SHIFT

    slot = slots.find { |candidate| candidate.id.to_s == value.to_s }
    slot ? alpha_acceptance_slot_label(slot) : value
  end
end
