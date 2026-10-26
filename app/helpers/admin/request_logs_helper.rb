# frozen_string_literal: true

module Admin::RequestLogsHelper
  REQUEST_LOG_FILTER_CHIP_LABELS = {
    person_callsign: "Person",
    status_class: "Outcome",
    http_method: "Verb",
    start_time: "From",
    end_time: "Until",
    ip: "Address"
  }.freeze

  # The Live mode's columns, in order. _live draws them and _live_rows hands
  # them to ui_table_rows for the fold's data-labels, so they are named once.
  REQUEST_LOG_LIVE_HEADINGS = %w[Timestamp Person Verb Status Request].freeze

  # How many rows the Live mode keeps on the page before dropping the oldest.
  REQUEST_LOG_LIVE_CAP = 200

  REQUEST_LOG_STATUS_VARIANTS = {
    "2xx" => :success,
    "3xx" => :secondary,
    "4xx" => :warning,
    "5xx" => :error
  }.freeze

  # One filter_bar chip per active filter. Each URL drops that one filter and
  # keeps the rest.
  def request_log_filter_chips(form)
    values = form.query_params[RequestLogFilterForm::PARAM_SCOPE]&.except(:page) || {}
    active = values.slice(*REQUEST_LOG_FILTER_CHIP_LABELS.keys)
    display = ->(key, value) { request_log_chip_value(form, key, value) }

    filter_chips(active, REQUEST_LOG_FILTER_CHIP_LABELS, value_label: display) do |remaining, _key|
      admin_request_logs_path(remaining.any? ? { RequestLogFilterForm::PARAM_SCOPE => remaining } : {})
    end
  end

  # Methods rather than the constants: ERB cannot resolve an included module's
  # constant unqualified.
  def request_log_live_headings = REQUEST_LOG_LIVE_HEADINGS

  def request_log_live_cap = REQUEST_LOG_LIVE_CAP

  # One of the two mode buttons above the log. The mode showing is the filled
  # button and says so in its accessible name, as the Radio Checkout view
  # buttons do (AssetManagement::RadioCheckoutHelper). Neither carries
  # aria-current, and data-active-ignore keeps active_links_controller from
  # adding one: Search's link has no query, so it would match on the path
  # alone and both buttons would read as current on the Live page.
  def request_log_mode_button(label, icon:, url:, current:)
    label = safe_join([label, tag.span(" (current view)", class: "sr-only")]) if current

    button_link label, current ? :primary : :secondary, url,
                { icon:, icon_type: :solid, data: { active_ignore: true } }
  end

  def request_log_person_label(row)
    person_display_link(row.person, row.person_id, blank: "-")
  end

  # The address alone, with the whole forwarded-for chain saved for the detail
  # row when an older entry carries one.
  def request_log_ip(row)
    row.client_ip || "-"
  end

  # The status number carries the meaning; the colour only repeats it, so a
  # reader who cannot tell the colours apart loses nothing.
  def request_log_status_badge(row)
    variant = REQUEST_LOG_STATUS_VARIANTS.fetch(request_log_status_class(row), :secondary)

    ui_badge(row.status.to_s, variant)
  end

  def request_log_size(row)
    number_to_human_size(row.response_size.to_i)
  end

  def request_log_duration(row)
    "#{number_with_precision(row.completion_time, precision: 2, delimiter: ',')} ms"
  end

  # True when this row has anything to open. Every row shows its address chain;
  # only a rejected request carries payloads.
  def request_log_payloads?(row)
    row.request_payload.present? || row.response_payload.present?
  end

  # A payload is stored as it arrived. JSON is laid out so it can be read, and
  # anything else -- an HTML page answering a rejected form -- is shown as is.
  def request_log_payload_block(payload)
    request_log_scrollable_block(request_log_pretty_payload(payload))
  end

  # Older entries hold JSON that was encoded a second time on the way in, so
  # the stored text is a quoted string rather than an object. Unwrapping it
  # once more is the difference between a readable payload and a wall of
  # backslashes.
  def request_log_pretty_payload(payload)
    value = payload.to_s

    2.times do
      parsed = request_log_parse_json(value)
      return value if parsed.nil?
      return JSON.pretty_generate(parsed) unless parsed.is_a?(String)

      value = parsed
    end

    value
  end

  private

  def request_log_status_class(row)
    RequestLog::STATUS_CLASSES.find { |_name, range| range.cover?(row.status.to_i) }&.first
  end

  def request_log_chip_value(form, key, value)
    case key
    when :start_time, :end_time then request_log_chip_time(form, key)
    when :status_class then RequestLog::STATUS_CLASS_OPTIONS.rassoc(value)&.first || value
    else value
    end
  end

  def request_log_chip_time(form, key)
    parsed = (key == :start_time) ? form.parsed_start_time : form.parsed_end_time
    parsed ? parsed.strftime(DateTimeHelper::CHIP_TIME) : form.public_send(key)
  end

  def request_log_parse_json(text)
    JSON.parse(text)
  rescue JSON::ParserError
    nil
  end

  def request_log_scrollable_block(content)
    ui_data_block(content, max_height: "max-h-80")
  end
end
