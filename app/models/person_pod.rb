# frozen_string_literal: true

# One person's membership of one pod.
#
# Three timestamps say three different things, and the difference matters:
#
#   joined_at  - when they were put in the pod.
#   left_at    - when the shift they joined on ended (stamped by
#                Timesheet#handle_shift_end through Pod.shift_ended). They are
#                still in the pod; they are just off duty.
#   removed_at - when a mentor took them out. This is the only one that ends
#                the membership, so every "who is in this pod" query filters
#                on it alone.
#
# Rows are never deleted on removal, so the roster of a past walk stays
# answerable. The [pod_id, person_id] index is deliberately not unique --
# someone removed and re-added has two rows, and that is the history.
#
# Upstream: app/Models/PersonPod.php.
class PersonPod < ApplicationRecord
  self.table_name = "person_pod"

  self.audit_model = true

  # Reordering a pod is not history -- see the same note on Pod.
  self.audit_exclude = ["sort_index"].freeze

  belongs_to :person
  belongs_to :pod

  scope :current, -> { where(removed_at: nil) }

  # Upstream's ordering: the explicit order first, then callsign for the rows
  # that share a number (mentor and mitten pods add everyone at 1).
  scope :ordered, -> { joins(:person).order(:sort_index).order("person.callsign") }

  before_create -> { self.joined_at ||= Current.time }
  # pod.person_count counts the current rows; a row destroyed outside Pod's own
  # paths (Person's deletion) refreshes it, disbanding an emptied pod.
  after_destroy -> { pod.refresh_person_count! }
end
