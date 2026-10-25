# frozen_string_literal: true

module Training::MenteesHelper
  FILTER_CHIP_LABELS = { status: "Status", rangering: "Rangering", callsign: "Callsign" }.freeze

  RANGERING_FILTERS = {
    "never" => "Never rangered",
    "stale" => "Stale 2+ years"
  }.freeze

  # The table's heading labels in column order. Shared by the index and by the
  # turbo_stream row replacement, which matches its responsive data-labels
  # against them by position -- so the two cannot drift.
  def mentees_headings(positions, can_revoke)
    ["Callsign", *positions.map(&:title), ("Action" if can_revoke)].compact
  end

  # The <tr> id the turbo_stream replacement targets.
  def mentees_row_id(mentee)
    "mentee-row-#{mentee.person.id}"
  end

  # The replace-one-row stream shared by revoke and restore. The row is rebuilt
  # through ui_table_rows so it keeps the classes and responsive data-labels of
  # the table it lands in -- a standalone <tr> has no thead to learn them from.
  def mentees_row_stream(mentee, revoked:)
    turbo_stream.replace mentees_row_id(mentee) do
      ui_table_rows headings: mentees_headings(mentee.grants.map(&:position), true),
                    striped: true do |t|
        render "training/mentees/row", t:, mentee:, revoked:, can_revoke: true
      end
    end
  end

  # The positions a just-revoked row can put back: what the person still shows
  # as holding, because the row was rendered from data captured before the
  # delete.
  def mentees_restorable_ids(mentee)
    mentee.grants.select(&:granted?).map { |grant| grant.position.id }
  end

  # One position's standing for one person: when it was granted, and when they
  # last rangered it. Never-rangered gets a badge rather than plain text --
  # it is the whole reason the page exists.
  def mentees_grant_cell(grant)
    return tag.span("Not granted", class: "text-stone-muted") unless grant.granted?

    tag.div(class: "flex flex-col gap-y-1") do
      safe_join([
                  tag.div("Granted #{grant.granted_year || "unknown"}"),
                  if grant.last_rangered_year
                    tag.div("Rangered #{grant.last_rangered_year}", class: "text-stone-muted tabular-nums")
                  else
                    ui_badge("Never rangered", :warning, icon: "circle-exclamation", icon_type: :solid)
                  end
                ])
    end
  end

  # Built from the statuses actually on the roster rather than a fixed list:
  # the report does not filter by status, so a mentee position can outlive the
  # account that holds it (retired, uberbonked) and those rows still need to be
  # findable -- they are the ones most likely to want revoking.
  def mentees_status_options(status_counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      status_counts.keys.sort.map { |status| ["#{status} (#{status_counts[status]})", status] }
  end

  def mentees_rangering_options(never_count, stale_count)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
     ["#{RANGERING_FILTERS["never"]} (#{never_count})", "never"],
     ["#{RANGERING_FILTERS["stale"]} (#{stale_count})", "stale"]]
  end

  def mentees_filter_chips(filter_params, slug)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:mentees_chip_value)) do |remaining|
      training_mentees_path(slug, **remaining)
    end
  end

  # Chips echo the words the page uses, not the raw param value.
  def mentees_chip_value(key, value)
    case key
    when :rangering then RANGERING_FILTERS.fetch(value, value)
    else value
    end
  end
end
