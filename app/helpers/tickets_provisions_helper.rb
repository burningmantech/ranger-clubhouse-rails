# frozen_string_literal: true

# Select options and formatting for the Tickets & Provisions pages, the person
# admin ones and Me › Tickets.
module TicketsProvisionsHelper
  # Grouped like the Ember admin form. SAP labels are spelled out here (the
  # model's short labels are for tables), so only the ticket/VP labels derive.
  ACCESS_DOCUMENT_TYPE_OPTIONS = [
    ["Regular Items", [
      [AccessDocument::TYPE_LABELS.fetch(AccessDocument::SPT), AccessDocument::SPT],
      [AccessDocument::TYPE_LABELS.fetch(AccessDocument::STAFF_CREDENTIAL), AccessDocument::STAFF_CREDENTIAL],
      ["Setup Access Pass", AccessDocument::SAP],
      ["S.O. Setup Access Pass", AccessDocument::SAPSO],
      [AccessDocument::TYPE_LABELS.fetch(AccessDocument::VEHICLE_PASS_GIFT), AccessDocument::VEHICLE_PASS_GIFT],
      [AccessDocument::TYPE_LABELS.fetch(AccessDocument::VEHICLE_PASS_SP), AccessDocument::VEHICLE_PASS_SP]
    ]],
    ["Gift Items", [
      [AccessDocument::TYPE_LABELS.fetch(AccessDocument::GIFT), AccessDocument::GIFT]
    ]],
    ["Late Season Directed", [
      [AccessDocument::TYPE_LABELS.fetch(AccessDocument::LSD), AccessDocument::LSD],
      ["LSD Vehicle Pass", AccessDocument::VEHICLE_PASS_LSD]
    ]]
  ].freeze

  ACCESS_DOCUMENT_STATUS_OPTIONS =
    (AccessDocument::CURRENT_STATUSES + AccessDocument::INVALID_STATUSES)
      .sort.map { |status| [status, status] }.freeze

  # Email is excluded: the model forces it for SAP types, it is never chosen.
  DELIVERY_METHOD_OPTIONS =
    AccessDocument::DELIVERY_LABELS.except(AccessDocument::DELIVERY_EMAIL)
                                   .map { |value, label| [label, value] }.freeze

  # Meals has no single model label (it is built from the period flags).
  PROVISION_TYPE_OPTIONS = [
    ["Meals", Provision::MEALS],
    [Provision::TYPE_LABELS.fetch(Provision::WET_SPOT), Provision::WET_SPOT],
    [Provision::TYPE_LABELS.fetch(Provision::EVENT_RADIO), Provision::EVENT_RADIO]
  ].freeze

  PROVISION_STATUS_OPTIONS =
    (Provision::CURRENT_STATUSES + Provision::INVALID_STATUSES)
      .map { |status| [status, status] }.freeze

  # Allocation is a boolean column, so the filter that reads it needs its own
  # vocabulary. One source for the select, the chip label, and the values the
  # controller will accept.
  PROVISION_ALLOCATED_OPTIONS = [["Allocated", "1"], ["Not allocated", "0"]].freeze

  def access_document_year_options
    year_span(9)
  end

  def provision_year_options
    year_span(4)
  end

  # Access date choices for SC / SAP / S.O. SAP documents: unspecified, any
  # time, or one of the setting-defined selectable dates. A current
  # out-of-range date is kept so editing doesn't silently drop it.
  def admission_date_options(document, ticketing_info)
    options = [["Unspecified", ""], ["Any time", AccessDocument::ADMISSION_ANY]]

    ticketing_info.sap_selectable_dates.each do |date|
      options << [wday_month_day_format(date, year: true), date.iso8601]
    end

    current = document.access_date&.to_date
    if current && options.none? { |_label, value| value == current.iso8601 }
      options << ["#{wday_month_day_format(current, year: true)} (current)", current.iso8601]
    end

    options
  end

  # Access-date table cell: "Any", the date, or an em dash.
  def access_date_label(document)
    if document.access_any_time
      "Any"
    elsif document.access_date
      # The person page lists documents from several years, so the date keeps its year.
      wday_month_day_format(document.access_date, year: true)
    else
      "—"
    end
  end

  # Display-formatted column diffs for one change-log row.
  def access_document_change_rows(change)
    change.diffs.map do |column, old_value, new_value|
      {
        column: column.to_s.titleize,
        old_value: change_value_label(old_value),
        new_value: change_value_label(new_value)
      }
    end
  end

  def change_value_label(value)
    value.to_s.presence || "blank"
  end

  # A price: "$40" for whole dollars, "$12.50" otherwise. The mail prices are
  # float settings, which "%g" printed as "$12.5". An unset setting is nil.
  def dollars(amount)
    return if amount.nil?

    number_to_currency(amount, precision: (amount % 1).zero? ? 0 : 2)
  end

  private

  def year_span(years_ahead)
    ((Current.year - 5)..(Current.year + years_ahead)).to_a
  end
end
