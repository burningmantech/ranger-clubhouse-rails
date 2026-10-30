# frozen_string_literal: true

# Cell rendering for the vehicle registry roster.
module Vehicles::RegistryHelper
  STATUS_BADGES = {
    Vehicle::APPROVED => ["Approved", :success, "circle-check"],
    Vehicle::PENDING => ["Pending", :warning, "clock"],
    Vehicle::REJECTED => ["Denied", :error, "circle-xmark"]
  }.freeze

  # The DB stores "rejected"; every label the reader sees says "Denied".
  STATUS_FILTER_OPTIONS = [
    UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
    ["Pending", Vehicle::PENDING],
    ["Approved", Vehicle::APPROVED],
    ["Denied", Vehicle::REJECTED]
  ].freeze

  TYPE_FILTER_OPTIONS = [
    UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
    ["Fleet", Vehicle::FLEET],
    ["Personal", Vehicle::PERSONAL]
  ].freeze

  PERMIT_FILTER_OPTIONS = ([UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
                           Vehicle::DRIVING_STICKER_OPTIONS).freeze

  SAP_FILTER_OPTIONS = [
    UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
    ["Has a Setup Access Pass", VehicleRegistry::SAP_PRESENT],
    ["No Setup Access Pass", VehicleRegistry::SAP_MISSING]
  ].freeze

  # One option per item the Items column can show. A flat list rather than
  # option groups: the three decal columns each have their own "None", which is
  # the absence of an item and not one of them, and a grouped picker would have
  # to offer three of those alongside the seven real answers.
  ITEM_FILTER_OPTIONS = [
    UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
    *Vehicle::RANGER_LOGO_OPTIONS.filter_map { |label, value| ["Ranger logo: #{label}", "ranger_logo:#{value}"] unless value == Vehicle::LOGO_NONE },
    *Vehicle::FUEL_CHIT_OPTIONS.filter_map { |label, value| ["Fuel chit: #{label}", "fuel_chit:#{value}"] unless value == Vehicle::FUEL_CHIT_NONE },
    *Vehicle::AMBER_LIGHT_OPTIONS.filter_map { |label, value| ["Amber light: #{label}", "amber_light:#{value}"] unless value == Vehicle::AMBER_LIGHT_NONE },
    ["Motor Vehicle Record", "org_vehicle_insurance:true"],
    ["Vehicle use agreement", "signed_motorpool_agreement:true"]
  ].freeze

  FILTER_LABELS = { status: "Status", type: "Type", number: "Number",
                    permit: "Driving permit", item: "Item",
                    sap: "Setup Access Pass" }.freeze

  # The picklist a chip's value has to be looked up in to be named.
  FILTER_OPTIONS = { status: STATUS_FILTER_OPTIONS, type: TYPE_FILTER_OPTIONS,
                     permit: PERMIT_FILTER_OPTIONS, item: ITEM_FILTER_OPTIONS,
                     sap: SAP_FILTER_OPTIONS }.freeze

  # Grouped select options that always include the value currently stored.
  #
  # Both of these columns are free text shared with the Laravel side, so a real
  # record can hold something the option list does not offer -- license_state
  # "NA" ("Not Available") is in the data today and is not in
  # CountryStateHelper. Without this, grouped_options_for_select marks nothing
  # selected, the blank option becomes the browser's default, and merely opening
  # the record and pressing Save erases the value.
  def options_including_current(grouped, current)
    known = grouped.values.flatten(1).map { |entry| entry.is_a?(Array) ? entry.last : entry }
    grouped = grouped.merge("Already on this record" => [[current, current]]) if current.present? && known.exclude?(current)

    grouped_options_for_select(grouped, current)
  end

  # Plain-text identity of one vehicle, for page titles and headings.
  def registry_vehicle_title(vehicle)
    owner = if vehicle.type == Vehicle::FLEET
              vehicle.team_assignment.present? ? "Fleet — #{vehicle.team_assignment}" : "Fleet vehicle"
            else
              vehicle.person&.callsign || "Owner deleted"
            end

    description = [vehicle.vehicle_year, vehicle.vehicle_make, vehicle.vehicle_model].compact_blank.join(" ")
    [owner, description.presence].compact.join(" — ")
  end

  def vehicle_status_badge(row)
    label, variant, icon = STATUS_BADGES.fetch(row.status) { [row.status.to_s.humanize, :secondary, "circle"] }
    ui_badge label, variant, icon:, icon_type: :solid
  end

  # Personal vehicles link to their owner; fleet vehicles name their team. A row
  # whose owner has since been deleted has no person_id left (the key sets it
  # NULL) and still has to render.
  def vehicle_owner(row)
    return fleet_owner(row) if row.fleet?
    return callsign_link(row.person) if row.person

    tag.span("Owner deleted", class: "italic text-stone-muted")
  end

  # "NV-7ABC123", built only from the parts that exist so a plateless fleet
  # truck does not render an orphan hyphen.
  def vehicle_plate(row)
    [row.license_state, row.license_number].compact_blank.join("-").presence
  end

  def vehicle_description_line(row)
    [row.vehicle_class, vehicle_plate(row) || "no plate on file"].compact_blank.join(" · ")
  end

  # Stickers, decals, chits and the two agreements, as pills. A denied request
  # gets none of them.
  def vehicle_items(row)
    return value_or_dash(nil) if row.status == Vehicle::REJECTED

    labels = []
    labels << "#{row.ranger_logo_label} logo" unless row.ranger_logo == Vehicle::LOGO_NONE
    labels << "#{row.fuel_chit_label} chit" unless row.fuel_chit == Vehicle::FUEL_CHIT_NONE
    labels << "#{row.amber_light_label} amber" unless row.amber_light == Vehicle::AMBER_LIGHT_NONE
    labels << "Motor Vehicle Record" if row.org_vehicle_insurance
    labels << "Vehicle use agreement" if row.signed_motorpool_agreement

    return value_or_dash(nil) if labels.empty?

    tag.div(safe_join(labels.map { |label| ui_badge(label, :secondary, size: "xs") }),
            class: "flex flex-wrap gap-2")
  end

  def vehicle_permit(row)
    return value_or_dash(nil) if row.status == Vehicle::REJECTED

    permit = row.driving_sticker_label
    permit = "#{permit} ##{row.sticker_number}" if row.sticker_number.present?
    parts = [tag.div(permit)]
    parts << tag.div("DPW #{row.rental_number}", class: "text-sm text-stone-muted") if row.rental_number.present?
    safe_join(parts)
  end

  # Fleet vehicles have no owner, so no Setup Access Pass applies. For any year
  # but the current one the lookup never ran, and saying "No SAP" there would
  # read as a confirmed absence rather than an unasked question.
  def vehicle_sap(row, enriched:)
    return value_or_dash(nil) unless row.person_id
    return tag.span("Not checked", class: "text-stone-muted") unless enriched

    vehicle_sap_display(row.arrival_date)
  end

  # arrival is VehicleRegistry::ARRIVAL_ANY, a Date, or nil for "none on file".
  def vehicle_sap_display(arrival)
    return ui_badge("Any", :success, icon: "circle-check", icon_type: :solid) if arrival == VehicleRegistry::ARRIVAL_ANY
    return wday_month_day_format(arrival) if arrival

    ui_badge("No Setup Access Pass", :error, icon: "circle-exclamation", icon_type: :solid)
  end

  # Only a personal vehicle whose owner was actually looked up has any of this,
  # and only an owner with at least one source has something to open.
  def vehicle_eligibility_details?(row, enriched:)
    enriched && row.personal? && row.person_id.present? && row.eligible?
  end

  def vehicle_eligibility_detail_id(row) = "vehicle-eligibility-#{row.id}"

  # The Details button, or -- for a pending request with nothing behind it --
  # the one line saying so. A blank cell there would read as "not looked at"
  # on exactly the row somebody is deciding on. An approved or denied row with
  # no sources gets neither: the decision is already made, and the line would be
  # noise on a page whose job is scanning.
  def vehicle_eligibility_control(table, row, enriched:)
    return nil unless enriched && row.personal? && row.person_id.present?

    unless row.eligible?
      return nil unless row.status == Vehicle::PENDING

      return tag.div("No eligible teams, positions, or sign-ups", class: "text-sm text-stone-muted")
    end

    table.detail_row_toggle("Details", id: vehicle_eligibility_detail_id(row),
                                       describing: "why #{row.person&.callsign} is eligible")
  end

  # Teams and held positions, each line labeled with which one it is: they are
  # different facts about the person, and an unlabelled merged list cannot be
  # acted on. paperwork_source_line is shared with the vehicle paperwork audit,
  # which renders the same two lines from its own data.
  def vehicle_eligibility_sources(teams:, positions:)
    lines = []
    lines << paperwork_source_line("Teams", teams) if teams.any?
    lines << paperwork_source_line("Positions", positions) if positions.any?

    return "none" if lines.empty?

    safe_join(lines)
  end

  def registry_filter_chips(filter_params, year)
    # :number is free text -- a permit could legitimately read "all" -- so it is
    # kept out of active_filters, which drops that value for every key.
    active = UiComponents::FilterBarHelper.active_filters(filter_params.except(:number))
    active[:number] = filter_params[:number] if filter_params[:number].present?

    filter_chips(active, FILTER_LABELS, value_label: method(:registry_filter_value_label)) do |remaining, _key|
      vehicles_registry_index_path(remaining.merge(year:))
    end
  end

  private

  def fleet_owner(row)
    safe_join([
                ui_badge("Fleet", :secondary, icon: "truck", icon_type: :solid),
                (tag.span(row.team_assignment) if row.team_assignment.present?)
              ].compact, " ")
  end

  # rassoc, not assoc: these are [label, value] select options, so the value
  # being looked up is the SECOND element.
  def registry_filter_value_label(key, value)
    FILTER_OPTIONS[key]&.rassoc(value)&.first || value
  end
end
