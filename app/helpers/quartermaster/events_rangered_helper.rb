# frozen_string_literal: true

module Quartermaster::EventsRangeredHelper
  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # "Service", not "Years" -- the chip reads "Service: 10 years", where
  # "Years: 10 years" would say it twice.
  FILTER_CHIP_LABELS = { status: "Status", years: "Service", signed_up: "Signed Up" }.freeze

  # Every URL this page builds carries status explicitly. An absent status
  # param means Active, so a link that simply dropped it -- the status chip's
  # "remove", or "clear all" -- would silently re-apply the filter it removed.
  # always: is what tells the shared builder that.
  def events_rangered_url(filters)
    filter_url(:quartermaster_events_rangered_path, filters, always: [:status])
  end

  # Under "All" the census carries deceased, dismissed and resigned rangers, so
  # a missing sign-up is not a gap anyone can act on. The amber is kept for a
  # scope where it is.
  def events_rangered_unsigned_variant(status)
    (status == ALL) ? :secondary : :warning
  end

  def events_rangered_filter_chips(filter_params)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:events_rangered_chip_value)) do |remaining|
      events_rangered_url(remaining)
    end
  end

  # Chips echo the words the page uses, not the raw param value.
  def events_rangered_chip_value(key, value)
    case key
    when :years then pluralize(value.to_i, "year")
    when :signed_up then value.titleize
    else value
    end
  end

  # One choice per service length present in the current status scope, longest
  # first, matching the order of the distribution table above it.
  #
  # The count is :matching, not :people -- this label is attached to a control
  # that navigates, so it has to promise the roster the choice delivers. With a
  # sign-up filter already applied the two differ, and printing :people here
  # offered "25 years (2)" and then handed over one person. A band that can
  # currently deliver no one still gets listed, reading "(0)": dropping it would
  # answer a narrowing request by widening.
  def events_rangered_years_options(distribution)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      distribution.map do |bucket|
        ["#{pluralize(bucket[:years], "year")} (#{bucket[:matching]})", bucket[:years].to_s]
      end
  end

  # Bars are read against each other, so they scale to the largest bucket rather
  # than to the roster total -- at 26 buckets a percentage of the whole would
  # leave every senior band invisible.
  def events_rangered_bar_percent(people, largest)
    return 0 if largest.to_i.zero?

    [(people * 100.0 / largest).round, 1].max
  end
end
