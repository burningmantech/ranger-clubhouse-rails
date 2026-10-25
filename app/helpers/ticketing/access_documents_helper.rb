# frozen_string_literal: true

module Ticketing::AccessDocumentsHelper
  # The Arrival column, resolved once for both the records table and its CSV
  # export so the two can never disagree.
  #
  # Returns [label, missing?]. The table styles the missing case and dashes the
  # types that never carry an access date, while the CSV writes the label as
  # plain text and leaves those types blank -- so callers need the label plus
  # the case that produced it.
  def arrival_label(document)
    return [nil, false] unless AccessDocument::HAS_ACCESS_DATE_TYPES.include?(document.type)
    return ["Anytime", false] if document.access_any_time
    return ["Missing", true] if document.access_date.blank?

    [wday_month_day_format(document.access_date), false]
  end

  # --- Summary filters -------------------------------------------------------

  # The two Arrival choices worth chasing: a document that should carry an
  # access date and does not, and one that lets the person in whenever they
  # like. URL value => the cell value it matches. The choices after these are
  # the found dates, keyed by ISO day; arrival_filter_value resolves both.
  ARRIVAL_FILTERS = {
    "missing" => AccessDocumentSummaryRow::ARRIVAL_MISSING,
    "anytime" => AccessDocumentSummaryRow::ARRIVAL_ANY_TIME
  }.freeze

  # The Weird Stuff checkbox's one "on" value; unchecked drops the param.
  ISSUES_ONLY = "1"

  # Tickets only -- what the Ticket and Special columns show -- not passes.
  # The records page is the one that filters on every type.
  SUMMARY_TICKET_TYPES = (AccessDocument::REGULAR_TICKET_TYPES + AccessDocument::SPECIAL_TICKET_TYPES).freeze

  SUMMARY_CHIP_LABELS = {
    status: "Status", type: "Ticket Type", person_status: "Person Status",
    arrival: "Arrival", issues: "Showing"
  }.freeze

  def summary_filter_chips(active_params)
    filter_chips(active_params, SUMMARY_CHIP_LABELS, value_label: method(:summary_filter_label)) do |remaining|
      ticketing_access_documents_path(remaining)
    end
  end

  # How a filter value reads, in its select and on its chip. Person statuses
  # print as stored; the rest are codes with a label.
  def summary_filter_label(key, value)
    case key
    when :status then value.humanize
    when :type then AccessDocument::TYPE_LABELS.fetch(value)
    when :arrival then arrival_filter_value(value).upcase_first
    when :issues then "People with issues"
    else value
    end
  end

  # The Arrival cell value a filter choice matches: Missing and Anytime by
  # name, a found date by its ISO day, spelled the way the column spells it.
  def arrival_filter_value(value)
    ARRIVAL_FILTERS.fetch(value) do
      Date.iso8601(value).strftime(AccessDocumentSummaryRow::ARRIVAL_DATE_FORMAT)
    end
  end

  # The Arrival choice a row falls under -- "missing", "anytime", or its ISO
  # day -- or nil when the cell is empty.
  def arrival_filter_choice(row)
    ARRIVAL_FILTERS.key(row.arrival.value) || row.arrival_date&.iso8601
  end

  # Options for one of the counted selects: `values` in the order the page
  # shows them; `held`, the page-wide {value => people} hash, decides which
  # are offered; `matching`, the same hash under the other active filters,
  # supplies the count. Like filter_status_options with matching:, a value
  # nobody on the page holds is left out, while one the other filters rule
  # out stays at (0) -- the choices never reshuffle as filters stack.
  def counted_filter_options(key, values, held, matching)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      values.filter_map { |value|
        ["#{summary_filter_label(key, value)} (#{matching.fetch(value, 0)})", value] if held.key?(value)
      }
  end

  # The Arrival select: Missing and Anytime first, then the found days in
  # date order.
  def arrival_filter_options(held, matching)
    named = ARRIVAL_FILTERS.keys
    ordered = held.keys.sort_by { |choice| [named.index(choice) || named.size, choice] }
    counted_filter_options(:arrival, ordered, held, matching)
  end
end
