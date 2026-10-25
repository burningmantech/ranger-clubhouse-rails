# frozen_string_literal: true

# Presentation registry for /mentoring/shift-report. The grouping itself --
# which positions form which group, in what order -- is the report's own
# (MentorShiftReport::GROUPS); only the icons and formatting live here.
module Mentoring::ShiftReportHelper
  GROUP_ICONS = {
    alphas: "seedling",
    mentors: "mitten",
    cheetahs: "paw",
    operations: "screwdriver-wrench"
  }.freeze
end
