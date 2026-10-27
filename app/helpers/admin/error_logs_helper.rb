# frozen_string_literal: true

module Admin::ErrorLogsHelper
  ERROR_LOG_FILTER_CHIP_LABELS = {
    person_callsign: "Person",
    error_type: "Type",
    start_time: "From",
    end_time: "Until"
  }.freeze

  ERROR_LOG_MASKED_VALUE = "[hidden]"

  # One filter_bar chip per active Error Log filter, plus "Last 24 hours" when
  # set. Each URL drops that one filter and keeps the rest.
  def error_log_filter_chips(form)
    values = form.query_params[ErrorLogFilterForm::PARAM_SCOPE]&.except(:page) || {}
    active = values.slice(*ERROR_LOG_FILTER_CHIP_LABELS.keys).reject { |_key, value| value.blank? }
    display = ->(key, value) { [:start_time, :end_time].include?(key) ? error_log_chip_time(form, key) : value }

    field_chips = filter_chips(active, ERROR_LOG_FILTER_CHIP_LABELS, value_label: display) do |_remaining, key|
      admin_error_logs_path(error_log_chip_params(values.except(key)))
    end

    field_chips + error_log_last_day_chip(values)
  end

  def error_log_person_label(person, person_id)
    person_display_link(person, person_id, blank: "-")
  end

  # A record with no IP came from background work rather than from a browser,
  # which is worth saying rather than showing the same dash a missing person
  # gets.
  def error_log_ip(row)
    row.ip.presence || "server"
  end

  # The URL as it is safe to show. Its query string can carry the same values
  # the payload hides -- a password reset link holds a working token -- so it
  # goes through the same filter.
  def error_log_display_url(url)
    return url if url.blank?

    uri = URI.parse(url)
    return url if uri.query.blank?

    filtered = error_log_parameter_filter.filter(Rack::Utils.parse_nested_query(uri.query)).to_query
    # Everything stays escaped except the marker itself, which is here to be
    # read rather than followed.
    uri.query = filtered.gsub(CGI.escape(ERROR_LOG_MASKED_VALUE), ERROR_LOG_MASKED_VALUE)
    uri.to_s
  rescue URI::InvalidURIError
    url.split("?").first
  end

  def error_log_metadata_items(row)
    method = error_log_data_value(row, "method")

    items = [["IP address", error_log_ip(row)]]
    items << ["Method", method] if method.present?
    items << ["URL", error_log_display_url(row.url)] if row.url.present?
    items << ["User agent", row.user_agent] if row.user_agent.present?
    items
  end

  # The exception details a record_exception call adds to `data`, or nil for
  # a record without one.
  def error_log_exception(row)
    exception = error_log_data_value(row, "exception")
    exception.is_a?(Hash) ? exception : nil
  end

  def error_log_exception_summary(exception)
    location = [exception["file"], exception["line"]].compact.join(":")
    [exception["message"], location.presence].compact.join(" — ")
  end

  def error_log_exception_stacktrace(exception)
    Array(exception["stacktrace"]).join("\n")
  end

  def error_log_pretty_data_block(row)
    error_log_scrollable_block(error_log_pretty_data(row), max_height: "max-h-80")
  end

  def error_log_stacktrace_block(exception)
    error_log_scrollable_block(error_log_exception_stacktrace(exception), max_height: "max-h-56")
  end

  def error_log_pager_summary(pagy)
    "Page #{pagy.page} of #{pagy.last} · #{pagy.count} total records"
  end

  private

  # The payload with sensitive values already replaced, so every part of the
  # row -- the exception, the metadata, the raw block -- reads from one masked
  # copy instead of each one remembering to hide things for itself.
  #
  # The filter walks hashes only: an array is wrapped for the trip so the
  # hashes inside it are still reached, and a bare scalar carries no keys to
  # hide.
  def error_log_filtered_data(row)
    case (data = row.data_or_nil)
    when Hash then error_log_parameter_filter.filter(data)
    when Array then error_log_parameter_filter.filter("payload" => data)["payload"]
    else data
    end
  end

  # One key out of the masked payload, or nil for a row with no data, non-hash
  # data, or a legacy row that never was valid JSON.
  def error_log_data_value(row, key)
    data = error_log_filtered_data(row)
    data[key] if data.is_a?(Hash)
  end

  def error_log_pretty_data(row)
    data = error_log_filtered_data(row)
    # A row that never held valid JSON cannot be hidden field by field, so it
    # is shown as stored -- the only way its contents stay readable at all.
    return row.data_before_type_cast.to_s.presence || "(no data)" if data.nil?

    JSON.pretty_generate(data)
  rescue JSON::GeneratorError, TypeError
    "(unreadable data)"
  end

  # Reuses the app's own configured filter_parameters list (config/initializers/
  # filter_parameter_logging.rb) so this page hides everything the rest of the
  # app already treats as sensitive, not a separately maintained guess.
  def error_log_parameter_filter
    @error_log_parameter_filter ||= ActiveSupport::ParameterFilter.new(
      Rails.application.config.filter_parameters, mask: ERROR_LOG_MASKED_VALUE
    )
  end

  def error_log_scrollable_block(content, max_height:)
    ui_data_block(content, max_height:)
  end

  def error_log_last_day_chip(values)
    return [] if values[:last_day].blank?

    [{ label: "Last 24 hours", url: admin_error_logs_path(error_log_chip_params(values.except(:last_day))) }]
  end

  def error_log_chip_params(values)
    cleaned = values.reject { |_key, value| value.blank? }
    cleaned.empty? ? {} : { ErrorLogFilterForm::PARAM_SCOPE => cleaned }
  end

  def error_log_chip_time(form, key)
    parsed = key == :start_time ? form.parsed_start_time : form.parsed_end_time
    parsed ? parsed.strftime(DateTimeHelper::CHIP_TIME) : form.public_send(key)
  end
end
