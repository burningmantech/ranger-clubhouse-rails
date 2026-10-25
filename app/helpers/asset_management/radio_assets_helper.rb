# frozen_string_literal: true

module AssetManagement::RadioAssetsHelper
  ALL_FILTER_OPTION = UiComponents::FilterBarHelper::ALL_FILTER_OPTION

  RADIO_ASSETS_CHIP_LABELS = { barcode: "Barcode", duration: "Duration",
                               description: "Description" }.freeze

  # One chip per active filter. Each URL drops that filter and keeps the view
  # params -- the year the reader chose, and which of the two tables they are
  # looking at. Page is dropped on purpose: a narrower filter can leave page 4
  # empty.
  def radio_assets_filter_chips(filter_params, view_params)
    display = ->(key, value) { key == :duration ? value.titleize : value }

    filter_chips(active_filters(filter_params), RADIO_ASSETS_CHIP_LABELS,
                 value_label: display) do |remaining|
      asset_management_radio_assets_path(remaining.merge(view_params).compact_blank)
    end
  end

  # The controller constant is named inside the method body on purpose: a helper
  # that resolves a controller constant while its own module body is loading
  # deadlocks both autoloads.
  def radio_assets_duration_options
    durations = AssetManagement::RadioAssetsController::DURATIONS

    [ALL_FILTER_OPTION, *durations.map { |duration| [duration.titleize, duration] }]
  end

  def radio_assets_description_options(descriptions)
    [ALL_FILTER_OPTION, *Array(descriptions).map { |description| [description, description] }]
  end

  def radio_range_badge(range)
    asset_assignment_badge(range.exemplar)
  end

  # The record page carries this radio's own checkout history plus its notes and
  # expiration. origin: sends its Back link back here rather than to the
  # inventory; type: is what its Cancel and Delete paths key on, and without it
  # they land on the bare types index instead of the radio type page.
  def radio_record_link(radio, index_params, page)
    link_to radio.barcode,
            asset_management_record_path(radio, **index_params, page:,
                                                type: Asset::TYPE_RADIO,
                                                origin: "radio-assets"),
            class: LinkHelper::TABLE_LINK_CLASSES
  end

  # Naming the rows the table actually shows. In the summarized view the rows
  # and the pager count ranges, so a count line reading "571 radios" over 50
  # rows invites the reader to divide one by the other.
  def radio_assets_result_count(summary_view, ranges, filtered_radios, radios)
    return "Showing #{filtered_radios.size} of #{pluralize(radios.size, "radio")}" unless summary_view

    "Showing #{pluralize(ranges.size, "barcode range")} " \
      "covering #{filtered_radios.size} of #{pluralize(radios.size, "radio")}"
  end

  # The sentinel never belongs in the text box -- it means "no barcode filter".
  def barcode_filter_value(barcode)
    barcode == UiComponents::FilterBarHelper::ALL_FILTER ? nil : barcode
  end
end
