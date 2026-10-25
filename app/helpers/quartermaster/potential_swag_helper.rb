# frozen_string_literal: true

module Quartermaster::PotentialSwagHelper
  # "Service Swag", not "Milestone" -- the chip reads "Service swag: 10-year",
  # the same words the summary line above it uses.
  FILTER_CHIP_LABELS = { status: "Status", milestone: "Service Swag",
                         signed_up: "Signed Up" }.freeze

  # No always: -- the page arrives unfiltered, so dropping a param already means
  # "off" for every filter here. Contrast Events Rangered, which defaults to
  # Active and so must spell status out in every URL it builds.
  def potential_swag_url(filters)
    filter_url(:quartermaster_potential_swag_path, filters)
  end

  def potential_swag_filter_chips(filter_params)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:potential_swag_chip_value)) do |remaining|
      potential_swag_url(remaining)
    end
  end

  # Chips echo the words the page uses, not the raw param value.
  def potential_swag_chip_value(key, value)
    case key
    when :milestone then "#{value}-year"
    # Not a status: the select spells this one "Yes" / "No", so the chip has to
    # as well.
    when :signed_up then value.titleize
    else value
    end
  end

  # One choice per milestone present in the current status scope, largest first,
  # matching the order of the summary above it.
  #
  # The count is :matching, not :people -- this label is attached to a control
  # that narrows, so it promises the roster the choice delivers alongside the
  # page's other filters AS THEY STAND. filter_bar applies its selects in one
  # batch, so changing the sign-up select in the same submit moves the answer
  # out from under this count; it is exact for a milestone picked on its own,
  # and an upper bound otherwise. A milestone that can currently deliver no one
  # is still listed, reading "(0)": dropping it would answer a narrowing
  # request by widening.
  def potential_swag_milestone_options(milestones)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      milestones.map do |line|
        ["#{line[:milestone]}-year service (#{line[:matching]})", line[:milestone].to_s]
      end
  end
end
