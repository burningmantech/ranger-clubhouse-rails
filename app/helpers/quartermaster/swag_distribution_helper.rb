# frozen_string_literal: true

module Quartermaster::SwagDistributionHelper
  FILTER_CHIP_LABELS = { category: "Category" }.freeze

  # What the year selector should show as chosen: the controller leaves @year
  # nil for the all-years view.
  def swag_distribution_selected_year
    @year || PageLayoutHelper::ALL_YEARS
  end

  # Every URL this page builds carries the year explicitly. The page's default
  # is the current year -- not an "off" state -- so a link that dropped ?year=
  # would silently jump an All-years or past-year reader back to the current
  # event.
  def swag_distribution_url(filters)
    filter_url(:quartermaster_swag_distribution_path,
               filters.merge(year: swag_distribution_selected_year))
  end

  def swag_distribution_filter_chips(filter_params)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:swag_distribution_chip_value)) do |remaining|
      swag_distribution_url(remaining)
    end
  end

  # Chips echo the page's own words, not the raw param value. Category is the
  # only filter this page has.
  def swag_distribution_chip_value(_key, value)
    SwagDistributionReport::CATEGORY_TITLES[value.to_sym] || value
  end

  # The categories with items in the current scope, in canonical order, each
  # with its item count -- offering the rest would be choices that can only
  # return nothing.
  #
  # The one exception is the category currently filtered on, which is listed
  # even at "(0)". The controller deliberately keeps such a filter, and the year
  # selector carries it across a year change, so dropping its option left the
  # select reading "All" while the chip said otherwise -- and Apply, which posts
  # every control whether or not it was touched, then silently widened a scope
  # the reader never changed.
  def swag_distribution_category_options(category_counts, applied)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      SwagDistributionReport::CATEGORIES.filter_map do |category|
        count = category_counts[category]
        next if count.zero? && category.to_s != applied

        ["#{SwagDistributionReport::CATEGORY_TITLES[category]} (#{count})", category.to_s]
      end
  end

  # One line per item: a muted category label, then the title. Category order
  # is canonical; within a category the items arrive title-sorted from the
  # report. Never colour alone -- the label is the text that carries the
  # category.
  #
  # text-stone-muted, not text-stone-muted: the latter currently resolves to the
  # same value as text-body, so the label it was meant to mute rendered
  # identically to the title beside it -- and this is the densest cell on the
  # page, where that separation is the whole readability strategy.
  def swag_item_lines(row)
    lines = SwagDistributionReport::CATEGORIES.flat_map do |category|
      Array(row.by_category[category]).map do |item|
        tag.div do
          safe_join([tag.span("#{SwagDistributionReport::CATEGORY_LABELS[category]}:",
                              class: "text-stone-muted"),
                     SwagDistributionReport.item_title(item, @year)], " ")
        end
      end
    end
    safe_join(lines)
  end
end
