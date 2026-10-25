# frozen_string_literal: true

module AssetManagement::AssetsOutstandingHelper
  OUTSTANDING_FILTER_CHIP_LABELS = { type: "Type" }.freeze

  # The type chip; its URL drops the filter and keeps the year, which the
  # selector needs back to stay on the year the reader chose.
  def assets_outstanding_filter_chips(filter_params, year)
    filter_chips(active_filters(filter_params), OUTSTANDING_FILTER_CHIP_LABELS,
                 value_label: ->(_key, value) { asset_type_label(value) }) do |remaining|
      asset_management_assets_outstanding_path(remaining.merge(year:).compact_blank)
    end
  end
end
