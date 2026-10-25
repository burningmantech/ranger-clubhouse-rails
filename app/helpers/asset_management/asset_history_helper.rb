# frozen_string_literal: true

module AssetManagement::AssetHistoryHelper
  ALL_FILTER_OPTION = UiComponents::FilterBarHelper::ALL_FILTER_OPTION

  ASSET_HISTORY_CHIP_LABELS = { type: "Type", outcome: "Outcome" }.freeze

  ASSET_HISTORY_OUTCOME_LABELS = {
    "returned" => "Returned",
    "outstanding" => "Never returned"
  }.freeze

  # One chip per active filter; each URL drops that filter and keeps the year,
  # which the year selector needs back to stay on the year the reader chose.
  # Page is dropped on purpose -- a narrower filter can leave page 4 empty.
  def asset_history_filter_chips(filter_params, year)
    display = lambda do |key, value|
      key == :outcome ? ASSET_HISTORY_OUTCOME_LABELS.fetch(value, value) : asset_type_label(value)
    end

    filter_chips(active_filters(filter_params), ASSET_HISTORY_CHIP_LABELS, value_label: display) do |remaining|
      asset_management_asset_history_path(remaining.merge(year:).compact_blank)
    end
  end

  # Every type the year holds, radios included. The default scope omits
  # handhelds, so the "all" label has to say so or it promises rows it does not
  # show.
  def asset_history_type_options(types)
    options = Array(types)
              .uniq
              .sort_by { |type| AssetManagement::RecordsHelper::ASSET_TYPE_SORT.fetch(type, Float::INFINITY) }
              .map { |type| [asset_type_label(type), type] }

    [["All except radios", ALL_FILTER_OPTION.last], *options]
  end

  def asset_history_outcome_options
    [ALL_FILTER_OPTION,
     *ASSET_HISTORY_OUTCOME_LABELS.map { |value, label| [label, value] }]
  end

  # An empty ledger has to say which kind of empty it is. The default scope
  # hides handheld radios, so "nothing went out" is a falsehood on a year whose
  # activity is all radios -- and the fix the reader needs is one filter away.
  def asset_history_empty_message(filter_params, year, hidden_radio_checkouts)
    return "No checkouts match these filters." if active_filters(filter_params).any?
    return "No checkouts were recorded for #{year} — nothing went out that year." unless
      hidden_radio_checkouts.to_i.positive?

    "Only handheld radios went out in #{year}. Choose Radio in the filters to see " \
      "#{pluralize(hidden_radio_checkouts, "checkout")}."
  end

  # How long the asset was actually gone. An open checkout has no such span:
  # PersonAsset#duration measures it to "now", which on a past year's ledger
  # states that a 2024 radio has been out for 730 days -- true, and useless
  # beside a row that already says "Never returned".
  #
  # hour_minute_words renders a twelve-day gear checkout as "295 hours 20 min".
  # Gear goes out for the whole event, so anything past a day is said in days.
  # person_asset.checked_out is NOT NULL in the schema, so a closed checkout
  # always has a real start to measure from.
  def asset_history_duration(history)
    return "—" if history.checked_in.blank?

    hour_minute_words_or_day_format(history.duration)
  end
end
