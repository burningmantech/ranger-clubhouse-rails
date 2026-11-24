# frozen_string_literal: true

# Draws Page Not Found for a request that ends in a 404: an address no route
# answers (the router's X-Cascade: pass), or an exception Rails maps to 404 --
# a record that is not there, a controller with no such action.
#
# Here, at the foot of the middleware stack, and not in the exceptions app
# (ErrorPages) above it: that one runs outside the session, flash and cookie
# middleware, so nothing a page drawn there writes is kept -- a flash message
# shows twice, a new CSRF token is never saved -- and Rack::Head and Rack::ETag
# never see its answer. Drawn here, the page is handled like any other.
#
# Only for a request for a page (ErrorPages.page?). A missing file, a fetch for
# JSON, a HEAD, and everything while Rails shows its debug pages (development,
# test) carry on as they were and end in the exceptions app or the debug page.
class NotFoundPage
  def initialize(app)
    @app = app
  end

  def call(env)
    begin
      response = @app.call(env)
      return response unless response[1][ActionDispatch::Constants::X_CASCADE] == "pass"
    rescue StandardError => e
      raise unless not_found?(e)
    end

    page(env) || response || raise(e)
  end

  private

  def page(env)
    ErrorsController.action(:not_found).call(env) if ErrorPages.page?(ActionDispatch::Request.new(env))
  end

  # As Rails itself will read it: a template error is the error it wraps.
  def not_found?(error)
    ActionDispatch::ExceptionWrapper.new(nil, error).status_code == 404
  end
end
