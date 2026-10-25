# frozen_string_literal: true

module Autocomplete
  # AssetAdapter turns a "#"-prefixed search request into an exact Asset.find_for_query
  # barcode lookup and normalizes the result into the unified autocomplete envelope.
  #
  # D2 (HARD CONSTRAINT): asset search matches ONLY asset-table columns (asset.barcode,
  # exact match — no LIKE). It NEVER queries the person table.
  #
  # Query shape:
  #   "#0042"        -> barcode "0042", year = Current.year
  #   "#0042:2024"   -> barcode "0042", year 2024
  #   "#0042:24"     -> non-4-digit year -> empty
  class AssetAdapter
    include Rails.application.routes.url_helpers

    GROUP_KEY = "asset"
    GROUP_TITLE = "Assets"
    MIN_QUERY_LENGTH = 2

    attr_reader :query, :mode, :limit, :filters

    def initialize(query:, mode: "asset", limit: 5, filters: {})
      @query = query
      @mode = mode
      @limit = limit
      @filters = filters
    end

    def search
      barcode, year = parse_query
      return empty_response(year:) if barcode.blank? || barcode.length < MIN_QUERY_LENGTH
      return empty_response(year:) if year.nil?

      assets = Asset.find_for_query(barcode:, year:)
      transform(assets.first(limit), year)
    end

    private

    # Strip the "#" prefix and all spaces, then parse an optional ":<year>" suffix.
    # Returns [barcode, year]; year is nil when the suffix is a non-4-digit year
    # (caller short-circuits to an empty result).
    def parse_query
      stripped = query.to_s.sub("#", "").delete(" ")

      if stripped.include?(":")
        base, year = stripped.split(":", 2)
        return [base, nil] unless year.to_s.match?(/\A\d{4}\z/)

        [base, year.to_i]
      else
        [stripped, Current.year]
      end
    end

    def transform(assets, year)
      return empty_response(year:) if assets.blank?

      items = []
      flat_ids = []

      assets.each do |asset|
        item_id = "a#{asset.id}"
        items << build_item(
          id: item_id,
          value: asset.barcode,
          label: "##{asset.barcode}",
          html: render_html(asset, year),
          # Result-click destination: the asset's global management page
          # (asset_management_record_path). The asset record is already resolved here.
          url: asset_management_record_path(asset.id),
          meta: {
            id: asset.id,
            barcode: asset.barcode,
            year: asset.year
          }
        )
        flat_ids << item_id
      end

      {
        filters: [],
        groups: [{ key: GROUP_KEY, title: GROUP_TITLE, item_ids: flat_ids }],
        flat_item_ids: flat_ids,
        items:
      }
    end

    def render_html(asset, year)
      ApplicationController.render(
        partial: "autocomplete/asset_item",
        locals: { asset:, year: }
      )
    end

    def build_item(id:, value:, label:, html:, meta: {}, url: nil)
      {
        id: id.to_s,
        value: value.to_s,
        label:,
        html:,
        url:,
        meta:
      }
    end

    def empty_response(year:)
      {
        empty_text: empty_text_for(year),
        filters: [],
        groups: [],
        flat_item_ids: [],
        items: []
      }
    end

    # Year-specific empty text.
    def empty_text_for(year)
      resolved = year || Current.year
      "No assets found for the #{resolved} event."
    end
  end
end
