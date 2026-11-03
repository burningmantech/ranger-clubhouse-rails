# frozen_string_literal: true

class ActiveStorageCacheControl
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)

    # Target Active Storage blob proxy paths
    if env["PATH_INFO"].start_with?("/rails/active_storage/blobs/proxy")
      headers["Cache-Control"] = "public, max-age=0"
    end

    [status, headers, response]
  end
end

