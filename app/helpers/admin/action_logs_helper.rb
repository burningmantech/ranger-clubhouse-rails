# frozen_string_literal: true

module Admin::ActionLogsHelper
  ACTION_LOG_MESSAGE_TRUNCATE_LENGTH = 40
  ACTION_LOG_EVENT_MAX_WIDTH = "max-w-[30ch]"
  ACTION_LOG_METADATA_LABEL_WIDTH = "12rem"

  ACTION_LOG_FILTER_CHIP_LABELS = {
    person_callsign: "User",
    target_person_callsign: "Target",
    start_time: "From",
    end_time: "Until",
    event_name: "Event",
    message: "Message"
  }.freeze

  ACTION_LOG_EVENT_FILTER_LABELS =
    ActionLogFilterForm::EVENT_FILTER_OPTIONS.to_h { |label, value| [value, label] }.freeze

  # One filter_bar chip per active Action Log filter (fields plus each event
  # category); each URL drops that filter, keeps the rest, and resets paging.
  # path: and category_labels: let the Legacy Clubhouse 1 Log, whose search
  # has the same fields, draw its chips with it.
  def action_log_filter_chips(form, path: :admin_action_logs_path, category_labels: ACTION_LOG_EVENT_FILTER_LABELS)
    values = form.query_params[ActionLogFilterForm::PARAM_SCOPE]&.except(:page) || {}
    active = values.slice(*ACTION_LOG_FILTER_CHIP_LABELS.keys).reject { |_key, value| value.blank? }
    display = ->(key, value) { [:start_time, :end_time].include?(key) ? action_log_chip_time(form, key) : value }

    # Chip URLs drop the field from the full values hash so event_filters survive.
    field_chips = filter_chips(active, ACTION_LOG_FILTER_CHIP_LABELS, value_label: display) do |_remaining, key|
      public_send(path, action_log_chip_params(values.except(key)))
    end

    category_chips = form.event_filters.map do |category|
      remaining = values.merge(event_filters: form.event_filters - [category])
      { label: "Category: #{category_labels.fetch(category, category)}",
        url: public_send(path, action_log_chip_params(remaining)) }
    end

    field_chips + category_chips
  end

  def action_log_person_label(person, person_id)
    return "Deleted ##{person_id}" if person_id.present? && person.blank?
    return "-" if person.blank?

    link_to(person.callsign, person_path(person), class: "link")
  end

  def action_log_toggle_label(timestamp, expanded: false)
    icon = expanded ? "chevron-up" : "chevron-down"

    content_tag(:span, class: "inline-flex items-center gap-1") do
      safe_join([
                  content_tag(:span, timestamp, class: "truncate"),
                  fa_icon(icon, :solid, class: "shrink-0 text-xs")
                ])
    end
  end

  def action_log_ip(row)
    row.ip.presence || "server"
  end

  # Plain text, every value: the view escapes them. The user agent is a request
  # header stored as it arrived, so nothing here may be marked html_safe.
  def action_log_metadata_items(row)
    items = [["IP address", action_log_ip(row)]]

    if row.browser.present?
      items << ["Browser", row.browser.values_at(:browser, :version, :platform).join(" • ")]
    end

    items << ["User agent", row.user_agent] if row.user_agent.present?
    items
  end

  def action_log_pretty_data(row)
    JSON.pretty_generate(normalize_action_log_data(row.data.presence || {}))
  rescue JSON::GeneratorError, JSON::ParserError, TypeError
    row.data.to_s
  end

  def action_log_pretty_data_block(row)
    ui_data_block(action_log_pretty_data(row))
  end

  def action_log_slots(row)
    [row.slot, *Array(row.enrolled_slots)].compact.uniq(&:id)
  end

  def action_log_positions(row)
    [row.position, *Array(row.positions)].compact.uniq(&:id).sort_by(&:title)
  end

  def action_log_teams(row)
    [row.team, *Array(row.teams)].compact.uniq(&:id).sort_by(&:title)
  end

  def action_log_roles(row)
    [row.role, *Array(row.roles)].compact.uniq(&:id).sort_by(&:title)
  end

  def action_log_inline_metadata_lines(row)
    lines = []

    slots = action_log_slots(row)
    if slots.any?
      lines << action_log_metadata_summary_line(slots.one? ? "Slot" : "Slots",
                                                slots.map { |slot| action_log_slot_summary(slot) })
    end

    positions = action_log_positions(row)
    if positions.any?
      lines << action_log_metadata_summary_line(positions.one? ? "Position" : "Positions",
                                                positions.map { |position| action_log_position_summary(position) })
    end

    teams = action_log_teams(row)
    if teams.any?
      lines << action_log_metadata_summary_line(teams.one? ? "Team" : "Teams",
                                                teams.map { |team| action_log_team_summary(team) })
    end

    lines
  end

  # message: the text to show when it is not the row's message column, as
  # the Legacy Clubhouse 1 Log's summary is.
  def action_log_message_cell(row, message: row.message)
    message = message.to_s
    return "-" if message.blank?
    return message if message.length <= ACTION_LOG_MESSAGE_TRUNCATE_LENGTH

    dom_id = "action-log-message-#{row.id}"
    content_tag(:span,
                data: {
                  controller: "read-more",
                  read_more_more_text_value: "Show More",
                  read_more_less_text_value: "Show Less"
                },
                class: "inline-block max-w-full") do
      safe_join([
                  content_tag(:span, truncate(message, length: ACTION_LOG_MESSAGE_TRUNCATE_LENGTH),
                              data: { read_more_target: "short" }),
                  content_tag(:span, message,
                              id: dom_id,
                              class: "hidden whitespace-pre-wrap break-words",
                              data: { read_more_target: "full" }),
                  # Below the 36px touch floor on purpose: this toggle sits on the
                  # text baseline inside the message paragraph, so `h-auto min-h-0`
                  # is what keeps it inline rather than breaking the line box. The
                  # standing exception is documented in design-foundations.
                  button_action("Show More", :ghost,
                                size: "xs",
                                class: "ms-1 h-auto min-h-0 px-1 align-baseline",
                                aria: { expanded: "false", controls: dom_id },
                                data: {
                                  read_more_target: "toggle",
                                  action: "click->read-more#toggle"
                                })
                ])
    end
  end

  # The ui_pager line, from ActionLog.find_for_query's result. Unfiltered, the
  # total is estimated from the id range, so there is no "of N" to promise.
  def action_log_pager_summary(result)
    total = result[:total]
    total_label = "#{number_with_delimiter(total)} total records"
    total_label = "Approximately #{total_label}" if result[:approximate_total]
    "Page #{result[:pagy].page} · #{total_label}"
  end

  private

  def normalize_action_log_data(value, depth = 0)
    return value if depth >= 3

    case value
    when Hash
      value.transform_values { |entry| normalize_action_log_data(entry, depth + 1) }
    when Array
      value.map { |entry| normalize_action_log_data(entry, depth + 1) }
    when String
      normalize_action_log_string(value, depth)
    else
      value
    end
  end

  def normalize_action_log_string(value, depth)
    stripped = value.strip
    return value if stripped.blank?

    parsed = JSON.parse(stripped)
    normalize_action_log_data(parsed, depth + 1)
  rescue JSON::ParserError
    value
  end

  def action_log_metadata_summary_line(label, items)
    safe_join([
                content_tag(:span, "#{label}:", class: "font-medium text-body"),
                " ",
                safe_join(items.map { |item| content_tag(:span, item) }, "; ".html_safe)
              ])
  end

  def action_log_slot_summary(slot)
    safe_join([
                "##{slot.id}",
                slot.position&.title || "Unknown position",
                datetime_format(slot.begins, tz: slot.timezone, tz_abbr: slot.timezone_abbr, year: true)
              ], " · ")
  end

  def action_log_position_summary(position)
    "##{position.id} · #{position.title}"
  end

  def action_log_team_summary(team)
    "##{team.id} · #{team.title}"
  end

  def action_log_chip_params(values)
    cleaned = values.reject { |_key, value| value.blank? }
    cleaned.empty? ? {} : { ActionLogFilterForm::PARAM_SCOPE => cleaned }
  end

  def action_log_chip_time(form, key)
    parsed = key == :start_time ? form.parsed_start_time : form.parsed_end_time
    parsed ? parsed.strftime(DateTimeHelper::CHIP_TIME) : form.public_send(key)
  end
end
