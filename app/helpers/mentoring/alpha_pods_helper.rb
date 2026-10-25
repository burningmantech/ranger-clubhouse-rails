# frozen_string_literal: true

# Presentation for Alpha Pod Management. Which pods exist and who is in them
# is AlphaPodBoard's business; this is only how they read on screen.
module Mentoring::AlphaPodsHelper
  # One icon per kind of sub-pod, so a card's three groups are told apart at a
  # glance rather than by reading their headings.
  GROUP_ICONS = {
    Pod::TYPE_MENTOR => "mitten",
    Pod::TYPE_MITTEN => "hand-sparkles",
    Pod::TYPE_ALPHA => "seedling"
  }.freeze

  def alpha_pod_group_icon(type) = GROUP_ICONS[type] || "users"

  # A pod's name for a heading or a sentence. Pod#number owns the rule; this
  # is only how it reads.
  def alpha_pod_name(pod) = pod.number ? "Pod #{pod.number}" : "Pod"

  # What the add dialog says beside a candidate's callsign: when they checked
  # in, what they checked in as, and -- for someone already picked up -- which
  # pod has them. The last one is why the row is disabled.
  def alpha_pod_candidate_note(candidate)
    parts = []
    # The check-in time carries the viewer's own timezone in a tooltip, the
    # same as every other time on these pages.
    parts << format_date(candidate.on_duty_at, "%H:%M") if candidate.on_duty_at
    parts << candidate.position_title if candidate.position_title.present?
    parts << "in Pod #{candidate.pod_number}" if candidate.assigned?
    return nil if parts.empty?

    safe_join(parts, " · ")
  end
end
