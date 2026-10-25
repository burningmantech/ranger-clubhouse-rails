# frozen_string_literal: true

# View helpers for the Alpha Mentor Assignments worksheet.
#
# The filter values live on AlphaMentorAssignment rather than on the controller:
# a helper that names a controller constant at load time makes the two autoloads
# wait on each other, and the controller loses its own class macros.
module Mentoring::AlphaMentorAssignmentsHelper
  ALL_FILTER = AlphaMentorAssignment::ALL_FILTER

  STATUS_FILTER_LABELS = {
    AlphaMentorAssignment::STATUS_PENDING_WITH_MENTORS => "Pending, mentors picked",
    AlphaMentorAssignment::STATUS_PASSED => "Passed",
    AlphaMentorAssignment::STATUS_BONKED => "Bonked"
  }.freeze

  def alpha_mentor_status_options
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      STATUS_FILTER_LABELS.map { |value, label| [label, value] }
  end

  # All / Not checked in / Checked in, then one option per shift in each of two
  # groups. Values carry a slot id rather than upstream's raw datetime string,
  # so nothing has to be parsed back out of the query string.
  def alpha_mentor_shift_options(slots, entries)
    checked_in_slot_ids = entries.filter_map { |entry| entry.shift_slot&.id }.to_set
    signed_up_slot_ids = entries.flat_map { |entry| entry.alpha_slots.map(&:id) }.to_set

    fixed = [
      UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
      ["Not checked in", AlphaMentorAssignment::SHIFT_NOT_CHECKED_IN],
      ["Checked in, any shift", AlphaMentorAssignment::SHIFT_CHECKED_IN]
    ]

    groups = [
      shift_option_group("Checked in for", slots, checked_in_slot_ids,
                         AlphaMentorAssignment::CHECKED_IN_PREFIX),
      shift_option_group("Signed up for", slots, signed_up_slot_ids,
                         AlphaMentorAssignment::SIGNED_UP_PREFIX)
    ].compact

    [fixed, groups]
  end

  # The two-part shift filter rendered for f.select. The fixed options stay
  # outside every optgroup, so the selection is baked in rather than passed as
  # `selected:` -- the two mechanisms fight when choices are pre-rendered.
  def alpha_mentor_shift_choices(slots, entries, selected)
    fixed, groups = alpha_mentor_shift_options(slots, entries)

    safe_join([
                options_for_select(fixed, selected),
                grouped_options_for_select(groups, selected)
              ])
  end

  # The mentor picker's groups, the way upstream groups them. Built once per
  # page and handed to MentorHelper#mentor_choices with each row's current
  # pick, because a page of Alphas renders three selects each.
  # @return [Array] the [group label, options] pairs
  def alpha_mentor_option_groups(pool, former)
    on_duty, off_duty = pool.partition(&:on_duty?)

    [
      # "On duty", never upstream's "working" -- banned UI vocabulary.
      ["On duty mentors", on_duty.map { |mentor| [mentor.callsign, mentor.id] }],
      ["Off duty mentors", off_duty.map { |mentor| [mentor.callsign, mentor.id] }],
      # Someone can lose the Mentor position after a walk. Their stored
      # assignment still has to render, or the select would silently blank and
      # the next save would drop a real record.
      ["No longer mentors", former.map { |mentor| [mentor.callsign, mentor.id] }]
    ].reject { |_label, options| options.empty? }
  end

  def alpha_mentor_slot_label(slot)
    description = slot.description.presence
    label = datetime_format(slot.begins, tz: slot.timezone, tz_abbr: slot.timezone_abbr)
    description ? safe_join([label, "<br>".html_safe, description]).html_safe : label
  end

  # The shifts the pod fill can read: every Alpha shift this year, each labelled
  # with how many pods it has.
  #
  # Shifts with no pods are listed rather than hidden. Upstream always offers
  # the button and only complains once a shift is picked, and hiding the control
  # until pods exist makes the whole feature look missing -- which is exactly
  # how it read on a season whose pods had not been formed yet.
  def alpha_mentor_pod_slot_options(slots, pod_counts)
    slots.map do |slot|
      count = pod_counts[slot.id].to_i
      suffix = count.zero? ? "no pods yet" : pluralize(count, "pod")

      ["#{strip_tags(alpha_mentor_slot_label(slot))} (#{suffix})", slot.id]
    end
  end

  def alpha_mentor_filter_chips(filter_params, slots)
    filter_chips(UiComponents::FilterBarHelper.active_filters(filter_params),
                 { status: "Status", shift: "Shift" },
                 value_label: ->(key, value) { alpha_mentor_chip_value(key, value, slots) }) do |remaining|
      mentoring_alpha_mentor_assignments_path(remaining)
    end
  end

  private

  def shift_option_group(label, slots, slot_ids, prefix)
    options = slots.select { |slot| slot_ids.include?(slot.id) }
                   .map { |slot| [strip_tags(alpha_mentor_slot_label(slot)), "#{prefix}#{slot.id}"] }
    return if options.empty?

    [label, options]
  end

  def alpha_mentor_chip_value(key, value, slots)
    return STATUS_FILTER_LABELS[value] || value if key == :status

    case value
    when AlphaMentorAssignment::SHIFT_NOT_CHECKED_IN then "Not checked in"
    when AlphaMentorAssignment::SHIFT_CHECKED_IN then "Checked in, any shift"
    else shift_chip_slot_label(value, slots)
    end
  end

  def shift_chip_slot_label(value, slots)
    prefix, id =
      if value.start_with?(AlphaMentorAssignment::CHECKED_IN_PREFIX)
        ["Checked in for", value.delete_prefix(AlphaMentorAssignment::CHECKED_IN_PREFIX)]
      else
        ["Signed up for", value.delete_prefix(AlphaMentorAssignment::SIGNED_UP_PREFIX)]
      end

    slot = slots.find { |candidate| candidate.id == id.to_i }
    slot ? "#{prefix} #{strip_tags(alpha_mentor_slot_label(slot))}" : value
  end
end
