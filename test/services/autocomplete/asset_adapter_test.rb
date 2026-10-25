# frozen_string_literal: true

require "test_helper"

class Autocomplete::AssetAdapterTest < ActiveSupport::TestCase
  setup do
    @person = person(:active_ranger)
    Current.person = @person
    Current.roles_manager = RoleManager.retrieve(@person)
  end

  test "matches an asset by exact barcode in the current year" do
    result = Autocomplete::AssetAdapter.new(query: "#RANGER1", mode: "asset", limit: 5).search

    ids = result[:items].map { |i| i[:meta][:id] }
    assert_includes ids, asset(:radio_current_year).id
    assert_not_includes ids, asset(:radio_prior_year).id, "prior-year row must not appear in current-year search"
    assert_equal 1, result[:groups].size
    assert_equal "asset", result[:groups].first[:key]
  end

  test "barcode match is exact (no LIKE / partial)" do
    # "#RANGER" (partial of "RANGER1") must NOT match the "RANGER1" barcode.
    result = Autocomplete::AssetAdapter.new(query: "#RANGER", mode: "asset").search

    assert_empty result[:items]
  end

  test ":<year> suffix scopes the search year" do
    scoped = Autocomplete::AssetAdapter.new(query: "#RANGER1:2024", mode: "asset").search

    ids = scoped[:items].map { |i| i[:meta][:id] }
    assert_includes ids, asset(:radio_prior_year).id
    assert_not_includes ids, asset(:radio_current_year).id
  end

  test "non-4-digit year suffix returns empty" do
    result = Autocomplete::AssetAdapter.new(query: "#RANGER1:24", mode: "asset").search

    assert_empty result[:items]
  end

  test "post-strip barcode below min length returns empty" do
    result = Autocomplete::AssetAdapter.new(query: "#A", mode: "asset").search

    assert_empty result[:items]
    assert_equal [], result[:flat_item_ids]
  end

  test "year-specific empty text" do
    result = Autocomplete::AssetAdapter.new(query: "#NOPE:2024", mode: "asset").search

    assert_equal "No assets found for the 2024 event.", result[:empty_text]
  end

  test "renders Year/barcode/type and guards nullable description" do
    with_desc = Autocomplete::AssetAdapter.new(query: "#RANGER1", mode: "asset").search
    html = with_desc[:items].first[:html]
    assert_match(/Year 2026/, html)
    assert_match(/#RANGER1/, html)
    assert_match(/HT Radio/, html)

    without_desc = Autocomplete::AssetAdapter.new(query: "#GEAR0042", mode: "asset").search
    assert_match(/#GEAR0042/, without_desc[:items].first[:html])
    # No trailing description text when description is nil.
  end

  test "asset result links to its ops asset management page" do
    result = Autocomplete::AssetAdapter.new(query: "#RANGER1", mode: "asset").search
    asset_record = asset(:radio_current_year)
    assert_equal Rails.application.routes.url_helpers.asset_management_record_path(asset_record.id), result[:items].first[:url]
  end

  test "emits the unified envelope shape with a single group and no filters" do
    result = Autocomplete::AssetAdapter.new(query: "#RANGER1", mode: "asset").search

    assert_equal [], result[:filters]
    assert_equal 1, result[:groups].size
    assert_equal result[:flat_item_ids].sort, result[:groups].first[:item_ids].sort
    item = result[:items].first
    assert item[:id].present?
    assert_equal "RANGER1", item[:value]
    assert item[:label].present?
    assert item[:html].present?
    assert item[:meta].is_a?(Hash)
  end

  # D2 GUARD: a person whose callsign equals an asset barcode must NEVER be returned;
  # asset search must never produce person rows.
  test "D2 guard: never returns a person whose callsign equals the barcode" do
    collision = person(:plate_collision_ranger)
    assert_equal "RANGER1", collision.callsign

    result = Autocomplete::AssetAdapter.new(query: "#RANGER1", mode: "asset").search

    assert result[:items].all? { |i| i[:id].start_with?("a") }
    returned_record_ids = result[:items].map { |i| i[:meta][:id] }
    assert_not_includes returned_record_ids, collision.id
    assert_equal [asset(:radio_current_year).id], returned_record_ids
  end

  # D2: matching is by asset.barcode only, independent of who is searching.
  test "D2 guard: results are not scoped to the current person" do
    Current.person = person(:retired_ranger)
    Current.roles_manager = RoleManager.retrieve(Current.person)

    result = Autocomplete::AssetAdapter.new(query: "#RANGER1", mode: "asset").search

    assert_equal [asset(:radio_current_year).id], result[:items].map { |i| i[:meta][:id] }
  end
end
