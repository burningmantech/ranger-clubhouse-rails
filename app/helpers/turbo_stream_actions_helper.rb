# frozen_string_literal: true

module TurboStreamActionsHelper
  def page_redirect(url)
    turbo_stream_action_tag :page_redirect, url:
  end
end

Turbo::Streams::TagBuilder.prepend(TurboStreamActionsHelper)
