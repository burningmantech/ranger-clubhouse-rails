# frozen_string_literal: true

module Autocomplete
  class ResponseBuilder
    DEFAULT_EMPTY_TEXT = "No results found"

    def self.build(query:, mode:, adapter_result:, request_id: nil)
      items = adapter_result[:items] || []
      # Honor an adapter-provided context-specific empty_text (e.g. "No people were
      # found matching callsign, name, or FKA"), falling back to the generic default.
      empty_text = items.empty? ? (adapter_result[:empty_text].presence || DEFAULT_EMPTY_TEXT) : nil

      {
        request_id: request_id || SecureRandom.uuid,
        query:,
        mode:,
        empty_text:,
        # banner text for the status-group disambiguation flow (nil when N/A)
        banner: adapter_result[:banner],
        filters: adapter_result[:filters] || [],
        groups: adapter_result[:groups] || [],
        flat_item_ids: adapter_result[:flat_item_ids] || [],
        items: items,
        meta: { result_count: items.size }
      }
    end
  end
end
