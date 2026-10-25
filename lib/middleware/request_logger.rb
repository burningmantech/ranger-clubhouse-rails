# frozen_string_literal: true

# Records every request the Clubhouse answers into the Request Log, and as a
# "page" event in the person's Action Log.
#
# Sits at the end of the middleware stack, closest to the application: Current
# still holds the signed-in person on the way back out, and the database
# connection is still checked out. Asset requests are served further up the
# stack and never reach here.
class RequestLogger
  # Requests that would bury the log without telling anyone anything: the
  # health check the load balancer polls, and the socket a page holds open.
  SKIP_PATHS = ["/up", "/cable"].freeze

  # Parameters and the complaint about them are the whole point of a rejected
  # request, and the only case worth storing a payload for.
  REJECTED_STATUS = 422

  # Pages whose rejected answer is not worth keeping, because the page it sends
  # back has the reader's own details filled into it. The parameters of a
  # rejected request are masked before they are stored; the page built from
  # those same parameters cannot be, so for these it is not stored at all.
  #
  # These are the pages a stranger can reach, where the details belong to
  # somebody who has no account and never agreed to the Clubhouse holding them.
  UNFILTERABLE_RESPONSE_PATHS = ["/register"].freeze

  # The url column holds 255 characters.
  URL_LIMIT = 255

  # A page about one person, by their id: the person pages and the HQ Window.
  # The audit question these answer is who looked at whom.
  PERSON_PATH = %r{\A(?:person|hq)/(\d+)(?:/|\z)}

  def initialize(app)
    @app = app
  end

  def call(env)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, headers, body = @app.call(env)
    record(env, status, headers, body, started_at)
    [status, headers, body]
  rescue => e
    # Nothing has turned this into a response yet, so record the status it is
    # about to become and let it carry on.
    record(env, status_for(e), {}, nil, started_at)
    raise
  end

  private

  # The status the reader will see for a failure. An exception on its way out
  # is turned into a response above this point -- a record that does not exist
  # becomes 404, a stale form token 422 -- so calling every one of them 500
  # would fill the failures filter with requests that never failed.
  def status_for(exception)
    ActionDispatch::ExceptionWrapper.new(nil, exception).status_code
  rescue
    500
  end

  def record(env, status, headers, body, started_at)
    request = ActionDispatch::Request.new(env)
    return unless record?(request)

    # One switch for the whole middleware: with recording off the Clubhouse
    # keeps no note of a request at all -- neither the entry in the Request Log
    # nor the page in the Action Log.
    return unless Setting.get_value(Setting::REQUEST_LOG_ENABLED)

    elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000
    path = path_for(request)

    RequestLog.record(
      person_id: Current.person&.id,
      ips: request.remote_ip.to_s,
      url: path,
      status: status,
      method: request.request_method,
      response_size: response_size(headers, body),
      completion_time: elapsed_ms,
      request_payload: request_payload(request, status),
      response_payload: response_payload(request, body, status)
    )

    # Rails' own paths are not pages anybody visited: an Active Storage
    # redirect is a page's images arriving, not a second visit to the page.
    return if path.start_with?("rails/")

    # The controller notes where a request came from only once the request gets
    # that far. A signed-out visitor sent to the sign-in page, a path nothing
    # answers and an outdated browser never do -- most of what a crawler asks
    # for -- and their visits would be recorded as coming from nowhere.
    Current.ip_address ||= request.remote_ip
    Current.user_agent ||= request.user_agent

    ActionLog.record(Current.person, "page-visit", path, nil, path[PERSON_PATH, 1]&.to_i)
  rescue => e
    # A request that was answered must not fail because the note about it
    # could not be written.
    Rails.logger.error("RequestLogger could not record a request: #{e.class}: #{e.message}")
    ErrorLog.record_exception(e, "page-request", request:)
  end

  def record?(request)
    request.request_method != "OPTIONS" && SKIP_PATHS.exclude?(request.path)
  end

  # The path alone. A query string can carry the same personal data the
  # payload filter hides, and it is not covered by that filter.
  def path_for(request)
    request.path.delete_prefix("/").presence&.truncate(URL_LIMIT) || "/"
  end

  def response_size(headers, body)
    length = headers["content-length"] || headers["Content-Length"]
    return length.to_i if length

    # A download is never read just to measure it -- that would pull the whole
    # file into memory for the sake of one number.
    return 0 if body.nil? || body.respond_to?(:to_path)

    body.respond_to?(:body) ? body.body.to_s.bytesize : 0
  end

  # Masked before it is stored. The filter is built here rather than taken
  # from the request, which only carries one once the application has put it
  # there -- and a password reaching this method unmasked is written to a
  # table people read.
  def request_payload(request, status)
    return nil unless status == REJECTED_STATUS

    values = readable_values(request.parameters.except("controller", "action"))

    JSON.generate(parameter_filter.filter(values))
  rescue
    nil
  end

  # An uploaded file has no useful text form -- writing one out gives an object
  # address and nothing else. Its name is the part worth keeping, and it can
  # sit at any depth, so the whole structure is walked.
  def readable_values(value)
    case value
    when ActionDispatch::Http::UploadedFile then value.original_filename
    when Hash then value.transform_values { |entry| readable_values(entry) }
    when Array then value.map { |entry| readable_values(entry) }
    else value
    end
  end

  def parameter_filter
    @parameter_filter ||= ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  end

  def response_payload(request, body, status)
    return nil unless status == REJECTED_STATUS && body.respond_to?(:body)
    return nil if UNFILTERABLE_RESPONSE_PATHS.include?(request.path)

    body.body
  end
end
