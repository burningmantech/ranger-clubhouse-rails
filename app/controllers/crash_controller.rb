# frozen_string_literal: true

# The crash page, for any answer in the 500s. Never routed: ErrorPages calls it.
#
# Not an ApplicationController on purpose: no sign-in lookup, gatekeeper or menu
# build runs here and the database is asked nothing, so whatever just broke
# cannot break this page too. Signed in is therefore only "carries the session
# cookie"; a stale one gets the dashboard link, and the dashboard sends a
# signed-out reader to the sign-in page.
class CrashController < ActionController::Base
  def show
    @signed_in = cookies.signed[:session_id].present?
    # The path alone: a query string can carry personal data.
    @path = request.env["action_dispatch.original_path"]
    @status = request.path_info.delete_prefix("/").to_i
    # Said here because nothing else will: the middleware that marks an
    # ordinary page private runs below the exceptions app, and the header
    # ApplicationController sets for the CDN is not inherited.
    no_store
    response.headers["CDN-Cache-Control"] = "max-age=0, no-store"
    render status: @status, formats: :html, layout: false
  end
end
