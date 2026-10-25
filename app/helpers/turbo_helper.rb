# frozen_string_literal: true

module TurboHelper
  def turbo_empty_frame(target_id)
    turbo_stream.update(target_id, "")
  end

  def turbo_response(streams)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
    end
  end
end
