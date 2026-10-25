# frozen_string_literal: true

module Training::OnlineCourseProgressHelper
  FILTER_CHIP_LABELS = { status: "Status", progress: "Progress", callsign: "Callsign" }.freeze

  # Filter keys (URL param values) and the labels the page shows for them.
  # Keys mirror Training::OnlineCourseProgressReport::PROGRESS_TESTS.
  PROGRESS_FILTERS = {
    "completed" => "Completed",
    "in-progress" => "In progress",
    "direct" => "Direct enrollment"
  }.freeze

  # A timestamp cell: the stored wall-clock stamp, or the blank marker for a
  # value the record does not have.
  def online_course_progress_time(time, blank = "—")
    return blank if time.blank?

    tag.span datetime_format(time), class: "whitespace-nowrap tabular-nums"
  end

  # Choices carry their counts, and a choice that can only return nothing is
  # omitted as noise -- same rules as the sibling reports.
  def online_course_progress_status_options(status_counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      Person::ALL_STATUSES.filter_map do |status|
        count = status_counts.fetch(status, 0)
        ["#{status} (#{count})", status] if count.positive?
      end
  end

  def online_course_progress_options(progress_counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      PROGRESS_FILTERS.filter_map do |key, label|
        count = progress_counts.fetch(key, 0)
        ["#{label} (#{count})", key] if count.positive?
      end
  end

  def online_course_progress_filter_chips(filter_params, slug, year)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:online_course_progress_chip_value)) do |remaining|
      training_online_course_progress_path(slug, **remaining, year:)
    end
  end

  # Chips echo the words the page uses, not the raw param value.
  def online_course_progress_chip_value(key, value)
    case key
    when :progress then PROGRESS_FILTERS.fetch(value, value)
    else value
    end
  end
end
