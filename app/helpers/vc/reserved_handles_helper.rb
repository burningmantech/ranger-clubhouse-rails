# frozen_string_literal: true

module Vc::ReservedHandlesHelper
  ALL_FILTER_OPTION = UiComponents::FilterBarHelper::ALL_FILTER_OPTION

  FILTER_CHIP_LABELS = {
    reservation_type: "Type",
    status: "Status"
  }.freeze

  def reserved_handle_type_label(value)
    HandleReservation::TYPE_LABELS.fetch(value, value)
  end

  def reserved_handle_type_options
    HandleReservation::TYPE_LABELS.map { |value, label| [label, value] }
  end

  def reserved_handle_type_filter_options
    [ALL_FILTER_OPTION, *reserved_handle_type_options]
  end

  def reserved_handle_status_filter_options
    [ALL_FILTER_OPTION, ["Active", "active"], ["Expired", "expired"]]
  end

  # One filter_bar chip per active filter ("all" selections are inactive);
  # each URL drops that filter and keeps the rest.
  def reserved_handle_filter_chips(filter_params)
    active = active_filters(filter_params)
    display = ->(key, value) { key == :reservation_type ? reserved_handle_type_label(value) : value.capitalize }

    filter_chips(active, FILTER_CHIP_LABELS, value_label: display) do |remaining|
      vc_reserved_handles_path(remaining)
    end
  end

  def reserved_handle_twii_default_date
    HandleReservation.default_twii_expires_on.strftime("%B %-d, %Y")
  end
end
