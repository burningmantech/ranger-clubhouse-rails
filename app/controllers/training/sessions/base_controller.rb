# frozen_string_literal: true

# Shared base for the session mutation controllers: the session is loaded and
# the viewer must hold the management ability (dirt MENTOR/VC are view-only).
# Roster and graduation controllers layer their stricter gates on top.
class Training::Sessions::BaseController < Training::BaseController
  before_action :load_session
  before_action :authorize_session_management

  private

  # Mutations respond to turbo form submissions; re-rendering the dialog with
  # the page's "modal" frame updated is the standard failure path.
  def update_modal(partial, locals)
    render turbo_stream: turbo_stream.update("modal", partial:, locals:),
           status: :unprocessable_entity
  end

  # Where every full-page mutation lands: back on the session page.
  def session_return_path
    training_session_path(training_slug, @training_session.slot.id)
  end
end
