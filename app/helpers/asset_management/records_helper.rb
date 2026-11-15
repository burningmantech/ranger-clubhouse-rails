# frozen_string_literal: true

module AssetManagement::RecordsHelper
  ALL_FILTER_OPTION = UiComponents::FilterBarHelper::ALL_FILTER_OPTION
  BLANK_FILTER_OPTION = "Blank"

  # asset.type is nullable in the Laravel-shared schema, so a row can arrive
  # without one. Those records still need a URL segment to be reachable.
  UNTYPED = "unspecified"

  ASSET_TYPE_LABELS = {
    Asset::TYPE_RADIO => "Radio",
    Asset::TYPE_DESKTOP_RADIO => "Desktop Radio",
    Asset::TYPE_MOBILE_RADIO => "Mobile/Vehicle Radio",
    Asset::TYPE_RADIO_CHARGER => "Radio Charger",
    Asset::TYPE_GEAR => "Gear",
    Asset::TYPE_TEMP_ID => "Temporary BMID",
    Asset::TYPE_AMBER => "Amber",
    Asset::TYPE_KEY => "Key",
    Asset::TYPE_VEHICLE => "Vehicle"
  }.freeze

  ASSET_TYPE_SORT = ASSET_TYPE_LABELS.keys.each_with_index.to_h.freeze

  ASSET_FILTER_CHIP_LABELS = {
    description: "Description",
    asset_group_id: "Asset group",
    entity_assignment: "Entity assignment",
    order_number: "Order number",
    expire: "Expires"
  }.freeze

  ASSET_EXPIRE_CHIP_VALUES = { "expired" => "Expired", "not-expired" => "Not expired" }.freeze

  # One filter_bar chip per active asset filter ("all" selections are
  # inactive); each URL drops that filter and keeps the rest. Type is not a chip
  # here -- it is the page, and dropping it would leave nowhere to land.
  def asset_filter_chips(filter_params, type, year)
    active = active_filters(filter_params)
    display = lambda do |key, value|
      case key
      when :expire then ASSET_EXPIRE_CHIP_VALUES.fetch(value, value)
      when :asset_group_id then AssetGroup.find_by(id: value)&.title || value
      else value
      end
    end

    filter_chips(active, ASSET_FILTER_CHIP_LABELS, value_label: display) do |remaining|
      asset_management_records_type_path(type, remaining.merge(year:).compact_blank)
    end
  end

  # Blank is reachable: asset.type is nullable in the Laravel-shared schema, and
  # a blank drill-down title raises.
  def asset_type_label(type)
    return "Unspecified" if type.blank?

    ASSET_TYPE_LABELS[type] || type.to_s.humanize
  end

  def asset_type_select_options
    ASSET_TYPE_SORT.keys.map { |type| [asset_type_label(type), type] }
  end

  def asset_type_records_path(type, **options)
    asset_management_records_type_path(type.presence || UNTYPED, **options)
  end

  def asset_type_filter_options(records)
    options = Array(records)
              .map(&:type)
              .uniq
              .sort_by { |type| ASSET_TYPE_SORT.fetch(type, Float::INFINITY) }
              .map { |type| [asset_type_label(type), type] }

    [ALL_FILTER_OPTION, *options]
  end

  def asset_filter_options(records, attribute)
    options = Array(records)
              .map { |asset| asset.public_send(attribute).presence || BLANK_FILTER_OPTION }
              .uniq
              .sort_by(&:to_s)
              .map { |value| [value, value] }

    [ALL_FILTER_OPTION, *options]
  end

  def asset_expire_filter_options(records)
    date_options = Array(records)
                   .filter_map { |asset| asset.expires_at&.to_date }
                   .uniq
                   .sort
                   .map { |date| [date.iso8601, date.iso8601] }

    [
      ALL_FILTER_OPTION,
      ["Expired", "expired"],
      ["Not expired", "not-expired"],
      *date_options
    ]
  end

  def asset_duration_label(asset)
    if asset.type == Asset::TYPE_RADIO
      asset.shift_only? ? "Shift" : "Event"
    else
      asset.shift_only? ? "Temporary" : "Permanent"
    end
  end

  # Shift and temporary assets are the ones due back soonest, so they carry the
  # warning colour; event and permanent assignments are out on purpose. Lives
  # beside the label it wraps rather than on any one page's helper: three of the
  # namespace's pages badge assets this way.
  def asset_assignment_badge(asset)
    ui_badge(asset_duration_label(asset), asset.shift_only? ? :warning : :secondary)
  end

  # The groups the records in hand use, by title; "Blank" when any has none.
  def asset_group_filter_options(records)
    records = Array(records)
    groups = records.filter_map(&:asset_group).uniq.sort_by { |group| group.title.downcase }
    blank = records.any? { |asset| asset.asset_group_id.nil? } ? [BLANK_FILTER_OPTION] : []

    [ALL_FILTER_OPTION, *blank, *groups.map { |group| [group.title, group.id] }]
  end

  def asset_group_status_badge(group)
    group.active? ? ui_badge("Active", :success) : ui_badge("Inactive", :secondary)
  end

  # A merge target as its select names it: an inactive one says so.
  def asset_group_merge_label(group)
    group.active? ? group.title : "#{group.title} (inactive)"
  end

  # Every asset group as the asset form's select wants it: by asset type, then
  # "Active" before "Inactive", an empty half left out. The asset-form
  # controller redraws the select from the same hash when the type changes.
  def asset_group_options_by_type
    @asset_group_options_by_type ||= AssetGroup.by_title.group_by(&:type).transform_values do |groups|
      active, inactive = groups.partition(&:active)
      { "Active" => active, "Inactive" => inactive }
        .reject { |_label, list| list.empty? }
        .transform_values { |list| list.map { |group| [group.title, group.id] } }
    end
  end
end
