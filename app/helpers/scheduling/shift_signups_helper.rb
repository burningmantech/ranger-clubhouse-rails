# frozen_string_literal: true

# Every method here is prefixed. Rails helper names share one namespace across
# the whole app, so a bare `fill_variant` would answer for every other page too.
module Scheduling::ShiftSignupsHelper
  # How covered something is: no one at all, thinly, or well enough. Takes
  # anything knowing its own sign-ups and seats -- an index row, a shift, or a
  # whole position.
  #
  # Red follows the sign-up count, not the percentage, so it always means what
  # the legend says. A few people against a limit of a thousand round down to
  # 0%, and calling that "no one signed up" would contradict the badge beside
  # it. Whether the rest is thin is the report's to answer, so there is one
  # definition of it rather than one per reader.
  def shift_signups_fill_variant(counts)
    if counts.sign_up_count.zero?
      :error
    elsif counts.low?
      :warning
    else
      :success
    end
  end

  # to_s because a well-covered row has no emphasis to add, and the view puts
  # this straight into a class list.
  def shift_signups_fill_emphasis(variant)
    severity_style(variant, :text).to_s
  end

  # Most rows carry no tint at all: only the two states worth pointing at do.
  #
  # :success is dropped rather than passed through, because this report and the
  # table component mean different things by it. Here it means "well covered,
  # nothing to say"; to `t.row state:` it means "the request just acted on this
  # row" and paints green. Handing the variant straight over would turn a
  # healthy report into a wall of green and leave the two real states with
  # nothing to stand out against.
  def shift_signups_row_state(counts)
    variant = shift_signups_fill_variant(counts)
    variant unless variant == :success
  end

  # Sign-ups against seats, or just the sign-ups when the shift takes as many
  # people as turn up.
  def shift_signups_count(sign_up_count, seat_count)
    seat_count.positive? ? "#{sign_up_count} of #{seat_count}" : sign_up_count.to_s
  end

  # What each way of narrowing the list is called, in the select and on its chip.
  def shift_signups_show_labels
    { Scheduling::ShiftSignupsController::SHOW_EMPTY => "With empty shifts",
      Scheduling::ShiftSignupsController::SHOW_LOW =>
        "Less than #{ShiftSignupsReport::LOW_FILL_PERCENTAGE}% full" }
  end

  def shift_signups_show_options
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      shift_signups_show_labels.map { |value, label| [label, value] }
  end

  def shift_signups_chips(filter_params, year)
    filter_chips(filter_params, { show: "Showing" },
                 value_label: ->(_key, value) { shift_signups_show_labels[value] }) do |remaining, _key|
      scheduling_shift_signups_path(**remaining, year:)
    end
  end

  # The schedule report names the people behind these counts. It admits the same
  # readers this page does, but asked rather than assumed, so the button cannot
  # go on promising a page that stopped admitting the reader.
  def shift_signups_can_view_schedule?
    Current.has_role?(Scheduling::ScheduleByPositionController.authorized_roles)
  end
end
