# frozen_string_literal: true

module Quartermaster::AlphaShirtsHelper
  # Shirt-kind labels come from ShirtTotals so a chip and its size run can only
  # ever call the same shirt the same thing.
  FILTER_CHIP_LABELS = ShirtTotals::KINDS.to_h { |kind| [kind[:param], kind[:name]] }
                                         .merge(status: "Status", missing: "Missing a size")
                                         .freeze

  # Only the two statuses this report can hold -- offering the rest would be
  # choices that can only return nothing.
  STATUSES = [Person::PROSPECTIVE, Person::ALPHA].freeze

  def alpha_shirts_filter_chips(filter_params)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:alpha_shirts_chip_value)) do |remaining|
      quartermaster_alpha_shirts_path(**remaining)
    end
  end

  # Chips echo the words the page uses, not the raw param value.
  def alpha_shirts_chip_value(key, value)
    case key
    when :missing then "Yes"
    else value
    end
  end

  # Both statuses carry their counts so the operator can see where the roster
  # sits before narrowing it.
  def alpha_shirts_status_options(status_counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      STATUSES.filter_map do |status|
        count = status_counts.fetch(status, 0)
        ["#{status} (#{count})", status] if count.positive?
      end
  end

  # One choice per size actually held, counted the same way. Sizes arrive in
  # run order with Unknown last, and the select keeps that order.
  def alpha_shirts_size_options(kind)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      kind.sizes.map { |size| ["#{size.title} (#{size.count})", size.title] }
  end
end
