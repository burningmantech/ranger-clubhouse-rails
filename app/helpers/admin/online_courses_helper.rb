# frozen_string_literal: true

module Admin::OnlineCoursesHelper
  COURSE_FOR_LABELS = {
    OnlineCourse::COURSE_FOR_ALL => "Everyone",
    OnlineCourse::COURSE_FOR_RETURNING => "Returning / Veterans",
    OnlineCourse::COURSE_FOR_NEW => "New / Applicant / Binary"
  }.freeze

  COURSE_FOR_OPTIONS = COURSE_FOR_LABELS.map { |value, label| [label, value] }.freeze

  def course_for_options
    COURSE_FOR_OPTIONS
  end

  def course_for_label(value)
    COURSE_FOR_LABELS.fetch(value, value)
  end

  def course_for_badge(value)
    variant = (value == OnlineCourse::COURSE_FOR_ALL) ? :primary : :secondary
    ui_badge(course_for_label(value), variant, size: "sm")
  end

  # The position's title, or a placeholder when the position row is gone. The
  # table carries no database link to position, so a position deleted
  # elsewhere leaves rows pointing at nothing -- printing the id keeps the
  # page readable and lets an admin find and clear the leftover.
  def position_title(position, position_id)
    position&.title || "Position ##{position_id}"
  end
end
