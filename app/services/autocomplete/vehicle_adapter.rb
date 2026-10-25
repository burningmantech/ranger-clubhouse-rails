# frozen_string_literal: true

module Autocomplete
  # VehicleAdapter turns a "!"-prefixed search request into a Vehicle.find_for_query
  # call and normalizes the matched vehicles into the unified autocomplete envelope.
  #
  # D2 (HARD CONSTRAINT): vehicle search matches ONLY vehicle-table columns
  # (license_number / rental_number / sticker_number via Vehicle.find_for_query).
  # It NEVER queries the person table and NEVER passes person_id. An owner person is
  # joined solely to render the "Owner <callsign>" label.
  #
  # Query shape:
  #   "!ABC123"        -> number "ABC123", event_year = Current.year
  #   "!ABC123:2024"   -> number "ABC123", event_year 2024
  #   "!ABC123:24"     -> non-4-digit year -> empty
  class VehicleAdapter
    include Rails.application.routes.url_helpers

    GROUP_KEY = "vehicle"
    GROUP_TITLE = "Vehicles"
    MIN_QUERY_LENGTH = 2

    attr_reader :query, :mode, :limit, :filters

    def initialize(query:, mode: "vehicle", limit: 5, filters: {})
      @query = query
      @mode = mode
      @limit = limit
      @filters = filters
    end

    def search
      number, event_year = parse_query
      # Reject blank/too-short numbers so empty-string vehicle-column defaults can't
      # LIKE-match every row.
      return empty_response(event_year:) if number.blank? || number.length < MIN_QUERY_LENGTH
      return empty_response(event_year:) if event_year.nil?

      vehicles = Vehicle.find_for_query(
        number:,
        status: Vehicle::APPROVED,
        event_year:
      )

      transform(vehicles.first(limit), event_year)
    end

    private

    # Strip the "!" prefix and all spaces, then parse an optional ":<year>" suffix.
    # Returns [number, event_year]; event_year is nil when the suffix is a non-4-digit
    # year (caller short-circuits to an empty result).
    def parse_query
      stripped = query.to_s.sub("!", "").delete(" ")

      if stripped.include?(":")
        base, year = stripped.split(":", 2)
        return [base, nil] unless year.to_s.match?(/\A\d{4}\z/)

        [base, year.to_i]
      else
        [stripped, Current.year]
      end
    end

    def transform(vehicles, event_year)
      return empty_response(event_year:) if vehicles.blank?

      items = []
      flat_ids = []

      vehicles.each do |vehicle|
        item_id = "v#{vehicle.id}"
        items << build_item(
          id: item_id,
          value: vehicle.id,
          label: vehicle_label(vehicle),
          html: render_html(vehicle, event_year),
          # Result-click destination: vehicles have no per-id global page, so an
          # OWNED vehicle routes to its owner's vehicle list; fleet/team vehicles
          # (no owner) are left unlinked (url nil -> no navigation).
          url: vehicle.person_id ? person_vehicles_path(vehicle.person_id) : nil,
          meta: {
            id: vehicle.id,
            event_year: vehicle.event_year,
            person_id: vehicle.person_id
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

    # Short text label for the input field (Owner/Team/Fleet), mirroring the HTML row.
    def vehicle_label(vehicle)
      if vehicle.person&.callsign.present?
        "Owner #{vehicle.person.callsign}"
      elsif vehicle.team_assignment.present?
        "Team #{vehicle.team_assignment}"
      else
        "Fleet Vehicle"
      end
    end

    def render_html(vehicle, event_year)
      ApplicationController.render(
        partial: "autocomplete/vehicle_item",
        locals: { vehicle:, event_year: }
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

    def empty_response(event_year:)
      {
        empty_text: empty_text_for(event_year),
        filters: [],
        groups: [],
        flat_item_ids: [],
        items: []
      }
    end

    # Year-specific empty text.
    def empty_text_for(event_year)
      year = event_year || Current.year
      "No vehicles found for the #{year} event."
    end
  end
end
