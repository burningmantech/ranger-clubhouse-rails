# frozen_string_literal: true

# Labels for the Timesheet Slot Repair page.
#
# Helper names are one global namespace no matter which module they sit in, so
# every method here is prefixed with the page it belongs to.
module Timesheets::SlotRepairHelper
  # One entry per group, in the order the page shows them. The three describe
  # what the change does to the entry, which is also what decides how much care
  # it deserves: removing a link loses information, adding one does not.
  SLOT_REPAIR_META = {
    add: { label: "Shift to add",
           heading: "Entries with no shift",
           aside: "These check-ins line up with a scheduled shift but were never linked to one.",
           icon: "link", variant: :warning },
    change: { label: "Shift to change",
              heading: "Entries linked to the wrong shift",
              aside: "These point at a shift for another position, or one too far from the check-in.",
              icon: "arrows-rotate", variant: :warning },
    remove: { label: "Shift to remove",
              heading: "Entries with no shift to point at",
              aside: "No scheduled shift matches these check-ins. Dropping the link loses " \
                     "the record of which shift the entry belonged to, so these start " \
                     "unticked. Pick them one at a time.",
              icon: "link-slash", variant: :error }
  }.freeze

  def slot_repair_meta(kind) = SLOT_REPAIR_META.fetch(kind)

  # Why this shift was picked over the others in the window.
  def slot_repair_reason(reason)
    case reason
    when TimesheetSlotRepair::SIGNED_UP then "Signed up for it"
    when TimesheetSlotRepair::ONLY_MATCH then "Closest shift to the check-in"
    end
  end
end
