# frozen_string_literal: true

# Wording and filter choices for the early arrivals report. Helper names share
# one namespace across the whole app, so everything here is prefixed.
module Scheduling::EarlyArrivalsHelper
  # How the filters are spelled in the URL. What each one is called on screen is
  # settled by the option lists below.
  SAP_ANY = "any"
  SAP_DATED = "dated"
  SAP_NONE = "none"
  SAP_FILTERS = [SAP_ANY, SAP_DATED, SAP_NONE].freeze

  SHIFT_YES = "yes"
  SHIFT_NO = "no"
  SHIFT_FILTERS = [SHIFT_YES, SHIFT_NO].freeze

  AGREEMENT_SIGNED = "signed"
  AGREEMENT_UNSIGNED = "unsigned"
  AGREEMENT_FILTERS = [AGREEMENT_SIGNED, AGREEMENT_UNSIGNED].freeze

  SITE_ON = "on"
  SITE_OFF = "off"
  SITE_FILTERS = [SITE_ON, SITE_OFF].freeze

  # What each filter is called on a chip.
  FILTER_CHIP_LABELS = {
    sap: "Arrival pass", arrival: "Arrives", shift: "Pre-event shift",
    shift_date: "Shift day", agreement: "Radio agreement", site: "Location"
  }.freeze

  ALL_OPTION = UiComponents::FilterBarHelper::ALL_FILTER_OPTION

  def early_arrival_sap_options
    [ALL_OPTION, ["Good any time", SAP_ANY], ["Dated", SAP_DATED],
     ["No pre-event pass", SAP_NONE]]
  end

  def early_arrival_shift_options
    [ALL_OPTION, ["Has one", SHIFT_YES], ["Has none", SHIFT_NO]]
  end

  def early_arrival_agreement_options
    [ALL_OPTION, ["Signed", AGREEMENT_SIGNED], ["Unsigned", AGREEMENT_UNSIGNED]]
  end

  def early_arrival_site_options
    [ALL_OPTION, ["On site", SITE_ON], ["Off site", SITE_OFF]]
  end

  # Only the days somebody is actually listed under. A day the report has no one
  # on would be a choice that can only come back empty.
  def early_arrival_date_options(dates)
    [ALL_OPTION] + dates.map { |date| [wday_month_day_format(date), date.to_s] }
  end

  def early_arrival_filter_chips(filter_params, year)
    filter_chips(filter_params, FILTER_CHIP_LABELS,
                 value_label: ->(key, value) { early_arrival_filter_value_label(key, value) }) do |remaining, _key|
      scheduling_early_arrivals_path(remaining.merge(year:))
    end
  end

  # A chip reads the way the choice did, not the way the URL spells it. The two
  # date filters are named rather than left to an else, so a filter added later
  # draws its raw value instead of being quietly run through a date formatter
  # that hands back an empty string.
  def early_arrival_filter_value_label(key, value)
    case key
    when :sap then { SAP_ANY => "Good any time", SAP_DATED => "Dated",
                     SAP_NONE => "No pre-event pass" }[value]
    when :shift then (value == SHIFT_YES) ? "Has one" : "Has none"
    when :agreement then value.capitalize
    when :site then (value == SITE_ON) ? "On site" : "Off site"
    when :arrival, :shift_date then wday_month_day_format(value)
    else value
    end
  end

  # When somebody may arrive. A pass good at any time carries no date, and a
  # missing pass is called out rather than left blank -- a packet cannot be put
  # together without one.
  # `live` is false on an earlier year, where no pass was ever recorded -- so the
  # cell says nothing was recorded rather than accusing everybody of not holding
  # one.
  def early_arrival_sap_cell(sap_date, live: true)
    return tag.span("Not recorded", class: "text-stone-muted") unless live

    case sap_date
    when :any then tag.span("Any time", class: "text-body")
    when nil then tag.span("No pre-event pass", class: "text-error font-semibold")
    else wday_month_day_format(sap_date)
    end
  end

  # The same answer in a spreadsheet cell, with no markup around it.
  def early_arrival_sap_export(sap_date)
    case sap_date
    when :any then "Any time"
    when nil then "None"
    else ymd_format(sap_date)
    end
  end

  # Badge wording comes from the one list the rest of the Clubhouse uses, so a
  # status cannot read one way here and another way on a person's own page.
  def early_arrival_bmid_label(status)
    return "No BMID" if status.blank?

    Bmid::ManageHelper::STATUS_LABELS.fetch(status, status)
  end

  def early_arrival_bmid_cell(status)
    return tag.span("No BMID", class: "text-error font-semibold") if status.blank?

    early_arrival_bmid_label(status)
  end

  # The radios somebody is holding, under how many they may draw. Colour never
  # carries the answer on its own: each line says event or shift in words.
  #
  # "None issued" is printed whatever the allowance, so a reader scanning the
  # column always sees an answer. A cell holding only a number reads like a row
  # that failed to finish drawing.
  def early_arrival_radios_cell(row)
    allowed = row.live ? "#{row.radios_allowed} allowed" : "Allowance not recorded"
    lines = [tag.div(allowed, class: "font-medium")]

    lines += if row.radios.any?
               row.radios.map { |radio|
                 tag.div("#{radio.barcode} (#{radio.label})", class: "text-sm text-body")
               }
             else
               [tag.div("None issued", class: "text-sm text-stone-muted")]
             end

    safe_join(lines)
  end

  # The one summary line above the table. "of N" appears only while a filter is
  # narrowing the list, so an unfiltered page does not say "131 of 131".
  def early_arrival_summary_count(shown:, total:)
    return "No one matches the current filters" if shown.zero?

    return pluralize(shown, "person") if shown == total

    "#{shown} of #{pluralize(total, "person")}"
  end
end
