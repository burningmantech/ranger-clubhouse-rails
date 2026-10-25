# frozen_string_literal: true

require "test_helper"

class Autocomplete::ResponseBuilderTest < ActiveSupport::TestCase
  test "builds response with all required fields" do
    result = {
      filters: [],
      groups: [],
      flat_item_ids: ["i1"],
      items: [{ id: "i1", value: "1", label: "Test", html: "<div>Test</div>", meta: {} }]
    }

    response = Autocomplete::ResponseBuilder.build(
      query: "test",
      mode: "person_manage",
      adapter_result: result
    )

    assert response[:request_id].present?
    assert_equal "test", response[:query]
    assert_equal "person_manage", response[:mode]
    assert_nil response[:empty_text]
    assert_equal [], response[:filters]
    assert_equal [], response[:groups]
    assert_equal ["i1"], response[:flat_item_ids]
    assert_equal 1, response[:items].size
    assert_equal 1, response[:meta][:result_count]
  end

  test "sets empty_text when no items" do
    result = {
      filters: [],
      groups: [],
      flat_item_ids: [],
      items: []
    }

    response = Autocomplete::ResponseBuilder.build(
      query: "xyz",
      mode: "person_manage",
      adapter_result: result
    )

    assert_equal "No results found", response[:empty_text]
    assert_equal 0, response[:meta][:result_count]
  end

  test "honors an adapter-provided empty_text over the default" do
    # The vehicle/asset adapters supply year-specific empty text; the builder must
    # surface it instead of the generic "No results found".
    result = {
      empty_text: "No vehicles found for the 2026 event.",
      filters: [],
      groups: [],
      flat_item_ids: [],
      items: []
    }

    response = Autocomplete::ResponseBuilder.build(
      query: "!zzz",
      mode: "vehicle",
      adapter_result: result
    )

    assert_equal "No vehicles found for the 2026 event.", response[:empty_text]
  end

  test "uses provided request_id when given" do
    result = { filters: [], groups: [], flat_item_ids: [], items: [] }

    response = Autocomplete::ResponseBuilder.build(
      query: "test",
      mode: "person_manage",
      adapter_result: result,
      request_id: "custom-id-123"
    )

    assert_equal "custom-id-123", response[:request_id]
  end

  test "generates request_id when not provided" do
    result = { filters: [], groups: [], flat_item_ids: [], items: [] }

    response = Autocomplete::ResponseBuilder.build(
      query: "test",
      mode: "person_manage",
      adapter_result: result
    )

    assert response[:request_id].present?
    assert_match(/\A[0-9a-f-]+\z/, response[:request_id])
  end

  test "preserves filter data from adapter" do
    result = {
      filters: [{
        key: "status",
        label: "Status",
        multi: false,
        options: [
          { value: "active", label: "Active", active: true, count: 5 }
        ]
      }],
      groups: [],
      flat_item_ids: [],
      items: []
    }

    response = Autocomplete::ResponseBuilder.build(
      query: "test",
      mode: "person_manage",
      adapter_result: result
    )

    assert_equal 1, response[:filters].size
    assert_equal "status", response[:filters].first[:key]
  end

  test "tolerates adapter_result with no items key" do
    response = Autocomplete::ResponseBuilder.build(
      query: "test",
      mode: "person_manage",
      adapter_result: {}
    )

    assert_equal "No results found", response[:empty_text]
    assert_equal [], response[:items]
    assert_equal 0, response[:meta][:result_count]
  end

  test "tolerates adapter_result with nil items" do
    response = Autocomplete::ResponseBuilder.build(
      query: "test",
      mode: "person_manage",
      adapter_result: { items: nil, filters: nil, groups: nil, flat_item_ids: nil }
    )

    assert_equal "No results found", response[:empty_text]
    assert_equal [], response[:items]
    assert_equal [], response[:filters]
    assert_equal [], response[:groups]
    assert_equal [], response[:flat_item_ids]
    assert_equal 0, response[:meta][:result_count]
  end

  test "preserves group data from adapter" do
    result = {
      filters: [],
      groups: [
        { key: "callsign", title: "Callsign", item_ids: ["i1"] }
      ],
      flat_item_ids: ["i1"],
      items: [{ id: "i1", value: "1", label: "Test", html: "<div>Test</div>" }]
    }

    response = Autocomplete::ResponseBuilder.build(
      query: "test",
      mode: "person_manage",
      adapter_result: result
    )

    assert_equal 1, response[:groups].size
    assert_equal "Callsign", response[:groups].first[:title]
  end
end
