# frozen_string_literal: true

class AutocompleteController < ApplicationController
  authorize_role [Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA]

  MIN_QUERY_LENGTH = 2

  # Inert message returned for a mode=hq request when the HQ Window search mode
  # is unavailable (interface setting off, or the viewer lacks Admin / Shift
  # Management).
  HQ_UNAVAILABLE_TEXT = "HQ search is not available"

  def search
    query = params[:q].to_s.strip
    mode = params[:mode].to_s.presence || "person_manage"
    limit = (params[:limit] || 5).to_i.clamp(1, 25)
    filters = parse_filters

    # The hq mode is gated exactly like the HQ Window pages themselves
    # (HQWindowInterfaceEnabled setting + Admin/Shift Management — see
    # SearchBarPolicy.hq_mode_available?). A crafted mode=hq request from anyone
    # else is short-circuited to an inert response; the mode is still echoed
    # back unchanged for the client.
    if mode == SearchBarPolicy::MODE_HQ && !SearchBarPolicy.hq_mode_available?
      return render(json: hq_unavailable_response(query:, mode:))
    end

    if query.length < MIN_QUERY_LENGTH
      return render json: {
        request_id: SecureRandom.uuid,
        query:,
        mode:,
        empty_text: "Type at least #{MIN_QUERY_LENGTH} characters to search",
        filters: [],
        groups: [],
        flat_item_ids: [],
        items: [],
        meta: { result_count: 0 }
      }
    end

    adapter_class = adapter_for(query)
    result = adapter_class.new(query:, mode:, limit:, filters:).search

    # Non person_manage modes send person results somewhere other than the
    # person-manage page the shared PersonAdapter pre-renders into item URLs.
    route_items_for_mode(result, mode) if adapter_class == Autocomplete::PersonAdapter

    render json: Autocomplete::ResponseBuilder.build(query:, mode:, adapter_result: result)
  rescue ActiveRecord::RecordNotFound
    render json: Autocomplete::ResponseBuilder.build(
      query:, mode:,
      adapter_result: { filters: [], groups: [], flat_item_ids: [], items: [] }
    )
  end

  private

  # Fetched by the search bar, never visited, and a sign-in redirect would
  # come back as the sign-in page. Say 401 and let the search bar explain (the
  # same as MegaMenuConcern).
  def request_authentication
    head :unauthorized
  end

  # Inert, well-formed envelope for an unavailable hq mode. Mirrors the
  # ResponseBuilder shape (empty groups/items) so the client renders the
  # "not available" empty state without any per-mode branching.
  def hq_unavailable_response(query:, mode:)
    Autocomplete::ResponseBuilder.build(
      query:, mode:,
      adapter_result: {
        empty_text: HQ_UNAVAILABLE_TEXT,
        filters: [], groups: [], flat_item_ids: [], items: []
      }
    )
  end

  # Rewrite person-item destinations for the mode: the HQ Window shell
  # redirector (/hq/N -> shift-manage when on site, otherwise site-registration),
  # the person timesheet page, or the person swag page. The person-manage
  # destination stays in Autocomplete::PersonAdapter#person_to_item, so that mode
  # -- and any mode the viewer may not use, which has no template -- is left
  # alone. Only person results reroute (a "!"/"#" prefixed vehicle/asset lookup
  # keeps its own destination).
  def route_items_for_mode(result, mode)
    return if mode == SearchBarPolicy::MODE_PERSON_MANAGE

    template = SearchBarPolicy.path_template_for(mode)
    return if template.nil?

    result[:items]&.each do |item|
      person_id = item.dig(:meta, :id)
      item[:url] = template.sub(":id", person_id.to_s) if person_id.present?
    end
  end

  # Prefix dispatch: the first character of
  # the trimmed query selects the search domain. "!" -> vehicle table, "#" -> asset
  # table (both D2: never the person table), "+"/default -> person. The "#"/"!" are
  # ordinary query-string param values (q=...), so they URL-decode into params[:q]
  # literally and are visible to first-char dispatch here.
  def adapter_for(query)
    case query[0]
    when "!"
      Autocomplete::VehicleAdapter
    when "#"
      Autocomplete::AssetAdapter
    else
      # "+id" lookups and bare text both go to the person adapter.
      Autocomplete::PersonAdapter
    end
  end

  def parse_filters
    raw = params[:filters]
    return {} if raw.blank?

    parsed = JSON.parse(raw)

    # v1: only accept a flat hash with string keys and string values
    return {} unless parsed.is_a?(Hash)

    parsed.each_with_object({}) do |(key, value), result|
      result[key.to_s] = value.to_s if value.is_a?(String) || value.is_a?(Numeric)
    end
  rescue JSON::ParserError
    {}
  end
end
