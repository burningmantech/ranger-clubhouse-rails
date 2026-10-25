# frozen_string_literal: true

# Every method here takes a shift_coverage_management_ prefix: helper names
# share one namespace, and Scheduling::ShiftCoverageHelper already speaks for
# the bare shift_coverage_ ones.
module Admin::ShiftCoverageManagementHelper
  # The positions a shift type or a post reads, one to a line: the title, with
  # "(inactive)" when the position is, then the label printed after a callsign,
  # in the same ink the report prints it in.
  #
  # entries are position ids or [position_id, label] pairs, and positions_by_id
  # is { id => Position }. A position that is not there reads as its number: it is
  # either gone or never existed in this database, and neither is a reason for
  # the page that lets an admin fix it to fail.
  def shift_coverage_management_position_lines(entries, positions_by_id)
    lines = entries.map do |entry|
      id, label = Array(entry)
      position = positions_by_id[id]
      title = position ? title_marking_inactive(position) : "Position ##{id}"
      label.present? ? safe_join([title, tag.span("(#{label})", class: "text-stone-subtle")], " ") : title
    end

    value_list(lines)
  end
end
