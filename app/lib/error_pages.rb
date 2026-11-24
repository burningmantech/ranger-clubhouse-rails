# frozen_string_literal: true

# What answers once a request has failed (config.exceptions_app). An answer in
# the 500s to a request for a page is the crash page; every other status, every
# other request, and any failure in here gets the static file in public/, as
# all of them did before. Page Not Found is not drawn here but inside the
# middleware stack (lib/middleware/not_found_page.rb, which says why), so a 404
# that reaches this point is one that page was not for, or could not draw.
#
# Rails calls this with the path rewritten to the status ("/500") and the
# method to GET; the address and method that failed are in
# action_dispatch.original_path and action_dispatch.original_request_method.
# It must not raise: Rails' answer to that is a bare line of text.
module ErrorPages
  STATIC = ActionDispatch::PublicExceptions.new(Rails.public_path)

  # An address someone reads as a page has no file extension, or .html. Any
  # other -- /favicon.ico, a scanner's /wp-login.php -- is a file that is not
  # there, and gets the small static answer.
  PAGE_EXTENSIONS = ["", ".html"].freeze

  def self.call(env)
    request = ActionDispatch::Request.new(env)
    return STATIC.call(env) unless request.path_info.delete_prefix("/").to_i >= 500 && page?(request)

    CrashController.action(:show).call(env)
  rescue StandardError => e
    record_failure(e, env)
    STATIC.call(env)
  end

  # Whether the request is for a page someone is looking at: a browser's
  # navigation or a Turbo form, for an address with no file extension. Not a
  # HEAD, which wants no body, and not while Rails shows its own debug pages
  # (development, test), which say more than these do.
  def self.page?(request)
    return false if request.get_header("action_dispatch.show_detailed_exceptions")

    path = request.get_header("action_dispatch.original_path") || request.path_info
    method = request.get_header("action_dispatch.original_request_method") || request.request_method
    method != "HEAD" && File.extname(path).in?(PAGE_EXTENSIONS) &&
      (request.format&.html? || request.format == :turbo_stream)
  rescue ActionDispatch::Http::MimeNegotiation::InvalidType
    false
  end

  # The crash page itself could not be drawn. The reader gets public/500.html;
  # the Error Log gets a row, or nobody would know. Not with the database gone:
  # there is nowhere to write it, and trying holds the request (RequestLogger).
  def self.record_failure(error, env)
    Rails.logger.error("ErrorPages fell back to public/: #{error.class}: #{error.message}")
    return if error.is_a?(ActiveRecord::ConnectionNotEstablished) || error.is_a?(ActiveRecord::ConnectionFailed)

    ErrorLog.record_exception(error, "error-page-exception", request: ActionDispatch::Request.new(env),
                                                             extra: { original_path: env["action_dispatch.original_path"] })
  rescue StandardError => e
    Rails.logger.error("ErrorPages could not record its failure: #{e.class}: #{e.message}")
  end
  private_class_method :record_failure
end
