# frozen_string_literal: true

# Cell rendering for the vehicle paperwork audit.
module Vehicles::PaperworkHelper
  APPROVAL_OPTIONS = [
    UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
    ["Approved", VehiclePaperworkReport::APPROVED],
    ["Not approved", VehiclePaperworkReport::NOT_APPROVED]
  ].freeze

  ELIGIBLE_OPTIONS = [
    UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
    ["Eligible", VehiclePaperworkReport::ELIGIBLE],
    ["Not eligible", VehiclePaperworkReport::NOT_ELIGIBLE]
  ].freeze

  # What each filter is called wherever it is named -- the panel label and the
  # chip that appears once it is set. One source so the two cannot disagree.
  FILTER_LABELS = {
    mvr_approval: "Motor Vehicle Record approval",
    mvr_eligible: "Motor Vehicle Record eligible",
    mvr_team: "Motor Vehicle Record team",
    mvr_position: "Motor Vehicle Record position",
    pvr_approval: "Personal vehicle agreement",
    pvr_eligible: "Personal vehicle eligible",
    pvr_team: "Personal vehicle team",
    pvr_position: "Personal vehicle position",
    callsign: "Callsign"
  }.freeze

  # Titles come from the roster, so they are already exactly what the row holds
  # -- no separate value/label mapping to drift.
  def paperwork_title_options(titles)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + titles.map { |title| [title, title] }
  end

  # The label a set filter shows on its chip. The picklists carry their own
  # wording; a title filter is its own label.
  #
  # rassoc, not assoc: these are select options, [label, value] pairs, so the
  # value being looked up is the SECOND element. assoc searches the labels,
  # finds nothing, and quietly leaves the chip reading "not_approved".
  def paperwork_filter_value_label(key, value)
    case key
    when :mvr_approval, :pvr_approval then APPROVAL_OPTIONS.rassoc(value)&.first
    when :mvr_eligible, :pvr_eligible then ELIGIBLE_OPTIONS.rassoc(value)&.first
    end || value
  end

  # One chip per active filter, each linking to the page with just that one
  # dropped.
  def paperwork_filter_chips(filters, year)
    filters.map do |key, value|
      { label: "#{FILTER_LABELS.fetch(key, key.to_s.humanize)}: #{paperwork_filter_value_label(key, value)}",
        url: vehicles_paperwork_path(filters.except(key).merge(year:)) }
    end
  end

  # Yes/no cells carry an icon as well as a color: this page is read by people
  # scanning a column for the gaps, and color alone would not survive that.
  def paperwork_flag(value, label)
    return ui_badge(label, :success, icon: "circle-check", icon_type: :solid) if value

    # A "No" is the thing being counted, not the thing being celebrated: it
    # stays quiet so the column reads as a run of gaps rather than a wall of
    # badges. The icon is what carries it for anyone who cannot see the color.
    tag.span(safe_join([fa_icon("circle-xmark", :regular), "No"]),
             class: "inline-flex items-center gap-2 text-stone-muted")
  end

  # The row's detail row is addressed by id from the toggle beside it.
  def paperwork_detail_id(row) = "paperwork-detail-#{row.person.id}"

  # The collapsed stand-in for the three "via" columns: how many of each source
  # there are, merged across both sides. This page is read for population
  # questions -- "who is eligible only because of a sign-up?" -- and a control
  # that says nothing until it is clicked answers those one person at a time.
  #
  # Every chip states its own value rather than disappearing at zero, so the
  # column keeps the same shape down the page and can be scanned. That is also
  # why the Event Info chip says "No Event Info" instead of dimming a chip that
  # reads the same either way.
  #
  # memberships_checked is false for any year but the current one, where an
  # empty team list means "never looked" -- the chip has to say so rather than
  # report a confident zero. Grants go unread there too, so the position chip
  # names the only kind it counted.
  def paperwork_source_counts(row, memberships_checked: true)
    teams = row.mvr_teams | row.pvr_teams
    positions = row.mvr_positions | row.pvr_positions
    event_info = row.mvr_checkbox || row.pvr_checkbox

    [memberships_checked ? [pluralize(teams.size, "team"), teams.any?] : ["Teams not checked", false],
     [pluralize(positions.size, memberships_checked ? "position" : "signed-up position"), positions.any?],
     [pluralize(row.mvr_signups.size, "sign-up"), row.mvr_signups.any?],
     [event_info ? "Event Info" : "No Event Info", event_info]]
  end

  # The chips are the control, so the whole cluster is one button.
  #
  # name:, not describing: -- the visible label here is markup, which cannot be
  # read into an accessible name, so this one is spelled out. The chips' own
  # text leads it, which is what keeps the button operable by voice.
  def paperwork_why_toggle(table, row, memberships_checked: true)
    counts = paperwork_source_counts(row, memberships_checked:)

    table.detail_row_toggle(paperwork_count_chips(counts),
                            id: paperwork_detail_id(row),
                            name: "Why #{row.callsign} is eligible: " \
                                  "#{counts.map(&:first).join(", ")}",
                            class: "flex-wrap justify-start")
  end

  def paperwork_count_chips(counts)
    chips = counts.map do |label, present|
      # A zero is still information here, so it stays legible rather than being
      # dropped -- it is only de-emphasised against the counts that matter.
      ui_badge(label, :secondary, class: ("opacity-60" unless present))
    end

    # No chevron: detail_row_toggle appends its own.
    safe_join(chips)
  end

  # One labelled group inside a row's opened detail. These were columns until
  # the three of them were folded into the detail row, and the heading is what
  # keeps each list identifiable now that the table header no longer names them.
  #
  # A helper rather than a partial: three of these per row over a 750-person
  # roster is 2,250 renders, and there is nothing here that needs a template.
  def paperwork_detail_group(title, &block)
    tag.div(class: "min-w-52") do
      safe_join([tag.h4(title, class: "heading-title text-stone-muted mb-1"),
                 tag.div(capture(&block), class: "text-sm")])
    end
  end

  # Everything that makes this person eligible, labeled by where it came from.
  # A team, a position and an Event Info checkbox are different facts about the
  # same person and the export keeps them in separate columns, so every line
  # here is labeled with which one it is rather than pouring all three into one
  # unlabelled list under a heading that names only two of them.
  #
  # positions_label says which positions these are: the Motor Vehicle Record
  # side lists grants, the personal vehicle side sign-ups.
  #
  # teams_checked / positions_checked are false for a list that was never read:
  # person_team and person_position keep no history, so for any year but the
  # current one an empty team or grant list means "never looked", not "none".
  def paperwork_sources(teams:, positions:, positions_label:, checkbox:,
                        teams_checked: true, positions_checked: true)
    lines = [paperwork_list_line("Teams", teams, checked: teams_checked),
             paperwork_list_line(positions_label, positions, checked: positions_checked)]
    lines << paperwork_source_line("Event Info", ["marked eligible"]) if checkbox
    lines.compact!

    return tag.div("- none -", class: "ms-4 italic") if lines.empty?

    safe_join(lines)
  end

  # A list that was never read says so; one that was read and came back empty
  # is left out, like any other source this person does not have.
  def paperwork_list_line(label, titles, checked:)
    unless checked
      return tag.div(safe_join([tag.span("#{label}: ", class: "text-stone-muted"),
                                tag.span("Not checked", class: "italic")]))
    end

    paperwork_source_line(label, titles) if titles.any?
  end

  def paperwork_source_line(label, titles)
    tag.div(safe_join([tag.div("#{label}:", class: "text-stone-muted font-semibold"), tag.div(titles.join(", "), class: "ms-4")]), class: "mb-2")
  end

  def paperwork_signups(signups)
    return tag.div("- none -", class: "ms-4 italic") if signups.empty?

    safe_join(signups.map do |signup|
      tag.div(safe_join([signup.position_title, " ", datetime_format(signup.begins, tz: signup.timezone)]),
              class: "whitespace-nowrap")
    end)
  end
end
