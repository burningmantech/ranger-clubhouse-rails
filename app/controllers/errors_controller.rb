# frozen_string_literal: true

# Page Not Found. Never routed: the NotFoundPage middleware calls it for a
# request that ended in a 404, sometimes after another controller already ran
# and failed in the same request, so params may hold that controller's values.
class ErrorsController < ApplicationController
  allow_unauthenticated_access
  # An error page answers. It never sends the reader somewhere else.
  skip_before_action :confine_past_prospective
  # It does nothing with what was sent, whatever the method was.
  skip_forgery_protection

  def not_found
    # The path alone: a query string can carry personal data.
    @path = request.path
    no_store
    render status: :not_found, formats: :html, layout: authenticated? ? "me" : "sessions"
  end
end
