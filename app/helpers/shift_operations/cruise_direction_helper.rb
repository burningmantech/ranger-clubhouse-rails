# frozen_string_literal: true

# Naming and formatting for the Cruise Direction page.
#
# Helper names are one global namespace in Rails, so everything here is
# cruise_direction_-prefixed.
module ShiftOperations::CruiseDirectionHelper
  # How a pod gets around, as the card and the form say it. Upstream's labels
  # and icons, which are what operators already read on the radio.
  TRANSPORT_DETAILS = {
    Pod::TRANSPORT_FOOT => { label: "On Foot", icon: "person-walking" },
    Pod::TRANSPORT_BICYCLE => { label: "Bike Mobile", icon: "bicycle" },
    Pod::TRANSPORT_VEHICLE => { label: "In Vehicle", icon: "truck-pickup" }
  }.freeze

  def cruise_direction_transport_label(transport)
    TRANSPORT_DETAILS.dig(transport, :label) || transport.to_s.humanize
  end

  def cruise_direction_transport_icon(transport)
    TRANSPORT_DETAILS.dig(transport, :icon) || "circle-question"
  end

  def cruise_direction_transport_options
    Pod::TRANSPORTS.map { |transport| [cruise_direction_transport_label(transport), transport] }
  end

  # What a pod is called everywhere on the page and in every message about it.
  #
  # Through Pod#number rather than off sort_index directly: the model owns that
  # rule, and Pod#guard_not_already_podded! builds its refusal from it -- so a
  # single response carrying both a card heading and an "already in Pod N"
  # toast has them agreeing by construction rather than by coincidence.
  def cruise_direction_pod_name(pod) = pod.number ? "Pod #{pod.number}" : "Pod"

  # The shift picker, grouped by day the way upstream groups it -- an event
  # week is two dozen shifts, and the day is how anyone finds one.
  def cruise_direction_shift_option_groups(shifts)
    shifts.group_by { |shift| wday_month_day_format(shift.begins, year: true) }
          .map { |day, group| [day, group.map { |shift| [cruise_direction_shift_label(shift), shift.id] }] }
  end

  # A shift as the picker lists it. The times are already local wall clock --
  # a slot's begins is stored in the event's timezone, so nothing converts.
  def cruise_direction_shift_label(shift)
    # The same stamp the Roll Call picker two pages over uses, so the two
    # shift-operations shift pickers read alike.
    "#{shift.begins.strftime(DateTimeHelper::MONTH_DAY_TIME)} - #{shift.ends.strftime(DateTimeHelper::HOUR_MINS)}"
  end

  # The state a shift is in, for the badge next to the picker. Nil for a shift
  # that has not started, which needs no badge at all.
  def cruise_direction_shift_status(slot)
    return [:secondary, "Ended", "circle-check"] if slot.has_ended
    return [:success, "Running now", "circle-play"] if slot.has_started

    nil
  end

  # Where Refresh goes. The shift on screen is named unless it is the one
  # running now: a page watching that one follows the clock onto whichever
  # shift runs next, while any other -- picked to build its pods early, or to
  # finish one off -- stays put.
  def cruise_direction_refresh_path(slot, shifts, year)
    running = slot.id == CruiseDirectionBoard.suggested_shift(shifts)&.id
    shift_operations_cruise_direction_path(slot_id: (slot.id unless running), year:)
  end
end
