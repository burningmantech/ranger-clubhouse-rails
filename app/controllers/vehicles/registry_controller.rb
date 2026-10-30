# frozen_string_literal: true

# The year's fleet and personal vehicles: triage pending personal-vehicle
# requests, maintain fleet records, and issue driving permits.
# Port of Ember ops/vehicle-registry.
class Vehicles::RegistryController < ApplicationController
  include CsvExportConcern

  layout "vehicles"

  # Upstream's CSV minus its duplicate SAP column, whose key was case-mismatched
  # against the row it was fed and so always exported empty.
  CSV_HEADERS = ["Person/Team", "Status", "SAP", "Vehicle Year", "Vehicle Make",
                 "Vehicle Model", "Vehicle Color", "Vehicle Class", "DPW Request ID",
                 "Driving Permit", "Permit #", "License State", "License #",
                 "Ranger Logo", "Fuel Chit", "Amber Light", "PVR Teams",
                 "PVR Positions", "Notes", "Response to person",
                 "Requester Comment"].freeze

  # Upstream's year selector floors at 2019 (ops/vehicle-registry.hbs:5); there
  # is no vehicle data before it.
  self.year_floor = 2019

  authorize_ability :view_registry,
                    roles: [], extra: :has_event_management?,
                    deny_to: :me_root_path,
                    message: "Event Management role required to view the vehicle registry."

  authorize_ability :edit_registry,
                    roles: [Role::VEHICLE_INFO_UPDATE],
                    only: %i[new create edit update],
                    deny_to: :registry_denied_path,
                    message: "Vehicle Info Update role required to edit vehicle records."

  authorize_ability :delete_registry,
                    roles: [], admin: true,
                    only: %i[destroy],
                    deny_to: :registry_denied_path,
                    message: "Admin permission required to delete vehicle records."

  # Recording a permit number is a window task, deliberately open to every
  # viewer -- but it is still a write, so it gets its own named ability rather
  # than riding on the read gate. Declared explicitly so the guard and the
  # affordance agree, and so widening or narrowing it is a one-line change.
  authorize_ability :issue_permit,
                    roles: [], extra: :has_event_management?,
                    only: %i[permit update_permit],
                    deny_to: :registry_denied_path,
                    message: "Event Management role required to issue driving permits."

  before_action :setup_year
  before_action :set_vehicle, only: %i[edit update destroy permit update_permit]

  def index
    load_index_state

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{@year}-vehicles.csv") }
    end
  end

  def new
    # Upstream's newEditAction defaults (ops/vehicle-registry.js:108).
    @vehicle = Vehicle.new(type: Vehicle::FLEET,
                           status: Vehicle::PENDING,
                           driving_sticker: Vehicle::DRIVING_STICKER_PREPOST,
                           vehicle_class: "Pickup Truck",
                           event_year: @year)
    load_form_state
  end

  def create
    @vehicle = Vehicle.new(vehicle_params)
    load_form_state

    if @vehicle.save
      redirect_to vehicles_registry_index_path(@return_index_params),
                  success: "#{vehicle_description(@vehicle)} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_form_state
  end

  def update
    load_return_paths

    if @vehicle.update(vehicle_params)
      redirect_to vehicles_registry_index_path(@return_index_params),
                  success: "#{vehicle_description(@vehicle)} updated."
    else
      # After the failed save, so the eligibility panel describes the owner the
      # re-rendered form is actually showing. Loading it first would pair the
      # new in-memory attributes with the old owner's lookups -- and a nil there
      # renders as a confident "No Setup Access Pass".
      load_eligibility if @vehicle.person_id
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @vehicle.destroy!

    redirect_to vehicles_registry_index_path(current_index_params),
                success: "#{vehicle_description(@vehicle)} deleted."
  end

  def permit
    @return_index_params = current_index_params
  end

  def update_permit
    @return_index_params = current_index_params

    if @vehicle.status == Vehicle::REJECTED
      return redirect_to permit_vehicles_registry_path(@vehicle, @return_index_params),
                         error: "This request was denied. Do not issue a permit for it."
    end

    # Writes the one column this page owns. @vehicle.update would re-run every
    # model validation, so a legacy row with, say, a blank team assignment would
    # reject the permit number on a page that offers no field to repair it.
    @vehicle.update_columns(sticker_number: permit_params[:sticker_number].to_s,
                            updated_at: Time.current)

    redirect_to vehicles_registry_index_path(@return_index_params),
                success: "Driving permit updated for #{vehicle_description(@vehicle)}."
  end

  private

  def load_index_state
    @filter_params = current_index_params.except(:year)
    # Links carry only the filters that are actually narrowing the list. The
    # "all" sentinel is present?, so it survives compact_blank and would ride
    # along in every URL; active_filters is the one place that drops it.
    # :number is free text -- a permit could legitimately read "all" -- so it is
    # re-added on plain presence, matching registry_filter_chips.
    narrowing = UiComponents::FilterBarHelper.active_filters(@filter_params.except(:number))
    narrowing[:number] = @filter_params[:number] if @filter_params[:number].present?
    @index_params = narrowing.merge(year: @year)

    @result = VehicleRegistry.for_year(@year, @filter_params)
  end

  def load_form_state
    load_return_paths
    load_eligibility if @vehicle.persisted? && @vehicle.person_id
  end

  def load_return_paths
    @return_index_params = current_index_params
    @cancel_path = vehicles_registry_index_path(@return_index_params)
  end

  # The MVR/PVR panel upstream fetches over XHR behind a blocking dialog
  # (full-edit.js:109). Every lookup is already in the app, so it renders inline.
  def load_eligibility
    person_id = @vehicle.person_id

    # Same current-year-only rule the roster follows: a prior year's pass was
    # never looked up, and the form simply omits the line.
    if @vehicle.event_year == Current.year
      @sap_arrival = VehicleRegistry.arrival_date_for(AccessDocument.find_sap_for_person(person_id))
    end

    @mvr_positions = Position.vehicle_eligible_for_person("mvr", person_id)
    @mvr_signups = PersonSlot.retrieve_mvr_signups(person_id, @vehicle.event_year)
    @mvr_teams = PersonTeam.retrieve_mvr_eligible_for_person(person_id)
    @pvr_positions = Position.vehicle_eligible_for_person("pvr", person_id)
    @pvr_teams = PersonTeam.retrieve_pvr_eligible_for_person(person_id)
  end

  def current_index_params
    params.permit(:year, *VehicleRegistry::FILTER_KEYS)
          .to_h
          .symbolize_keys
          .compact_blank
          .merge(year: @year)
  end

  def set_vehicle
    @vehicle = Vehicle.includes(:person).find(params[:id])
  end

  def vehicle_params
    permitted = params.expect(vehicle: [:type,
                                        :callsign,
                                        :team_assignment,
                                        :event_year,
                                        :status,
                                        :vehicle_class,
                                        :vehicle_year,
                                        :vehicle_make,
                                        :vehicle_model,
                                        :vehicle_color,
                                        :rental_number,
                                        :license_state,
                                        :license_number,
                                        :driving_sticker,
                                        :sticker_number,
                                        :fuel_chit,
                                        :ranger_logo,
                                        :amber_light,
                                        :notes,
                                        :response,
                                        :request_comment])

    force_staff_sticker_for_fleet(permitted)
  end

  # Upstream forces this client-side only (ops/vehicle-registry.js:162), so the
  # API accepts a fleet record carrying any sticker. Resolve the type from the
  # request when it is there and from the persisted record when it is not, so a
  # PATCH that simply omits :type cannot slip past the rule.
  def force_staff_sticker_for_fleet(permitted)
    resolved_type = permitted[:type].presence || @vehicle&.type
    permitted[:driving_sticker] = Vehicle::DRIVING_STICKER_STAFF if resolved_type == Vehicle::FLEET
    permitted
  end

  def permit_params
    params.expect(vehicle: [:sticker_number])
  end

  def vehicle_description(vehicle)
    owner = if vehicle.type == Vehicle::FLEET
              vehicle.team_assignment.presence || "Fleet vehicle"
            else
              vehicle.person&.callsign || "Vehicle"
            end

    [owner, vehicle.vehicle_make, vehicle.vehicle_model].compact_blank.join(" ")
  end

  # An editor denied the edit gate can still read the roster; send them back to it.
  def registry_denied_path
    vehicles_registry_index_path(year: @year || Current.year)
  end

  def csv_rows
    [CSV_HEADERS] + @result.rows.map { |row| csv_row(row) }
  end

  def csv_row(row)
    [csv_owner(row),
     row.status,
     csv_enriched(row) { csv_arrival_date(row) },
     row.vehicle_year,
     row.vehicle_make,
     row.vehicle_model,
     row.vehicle_color,
     row.vehicle_class,
     row.rental_number,
     # Nothing is issued for a denied request, so the sheet carried to the
     # issuing table must not list any of it -- the roster already blanks these
     # cells, and the export is the copy people actually act on.
     csv_issuable(row) { row.driving_sticker_label },
     csv_issuable(row) { row.sticker_number },
     row.license_state,
     row.license_number,
     csv_issuable(row) { row.ranger_logo_label },
     csv_issuable(row) { row.fuel_chit_label },
     csv_issuable(row) { row.amber_light_label },
     csv_enriched(row) { row.pvr_teams.join("\n") },
     csv_enriched(row) { row.pvr_positions.join("\n") },
     row.notes,
     row.response,
     row.request_comment]
  end

  def csv_owner(row)
    return row.team_assignment.presence || "Fleet vehicle" if row.fleet?

    row.person&.callsign || "Owner deleted"
  end

  # Stickers, decals and chits for a denied request: there are none to issue.
  def csv_issuable(row)
    return "" if row.status == Vehicle::REJECTED

    yield
  end

  # A blank enrichment cell means "confirmed none" in a current-year sheet. For
  # any other year nothing was ever looked up, and saying so is the honest export.
  def csv_enriched(row)
    return "" unless row.person_id
    return "not checked" unless @result.enriched?

    yield
  end

  def csv_arrival_date(row)
    return VehicleRegistry::ARRIVAL_ANY if row.arrives_any_time?

    row.arrival_date&.iso8601 || ""
  end
end
