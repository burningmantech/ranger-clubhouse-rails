require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system unless the server names another
  # config/storage.yml service: AWS sets RANGER_CLUBHOUSE_STORAGE_SERVICE=amazon.
  config.active_storage.service = ENV.fetch("RANGER_CLUBHOUSE_STORAGE_SERVICE", "local")
  config.active_storage.resolve_model_to_route = :rails_storage_proxy

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [:request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Rails.cache is the Redis beside Puma: the compose `redis` service, or the redis-server that
  # bin/docker-server starts in the AWS image: 128 MB, least-recently-used eviction, nothing on
  # disk. While Redis is down the store logs and answers a miss, a second per call, so Redis
  # starts first.
  config.cache_store = :redis_cache_store, { url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0") }

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
  # How long a deploy waits for a running job before letting it go to start
  # over. Longer than one broadcast email call can take (Rbs.ses_client), so a
  # batch is never cut off mid-call and sent twice. docker-compose.yml's
  # stop_grace_period must stay longer still.
  config.solid_queue.shutdown_timeout = 30.seconds

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates. Twilio's
  # webhooks are checked against it too (TwilioSignatureConcern.address), so it
  # must be the name Twilio is given for this server.
  config.action_mailer.default_url_options = { host: ENV["RANGER_CLUBHOUSE_HOST"].presence || "clubhouse3.dev" }
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: "mailpit",
    port: 1025
  }

  # Broadcast email goes out through Amazon SES, and reaches Rangers only once
  # this is switched on for the server. Anything else running as production
  # with the same keys -- a restored copy, say -- holds it back.
  config.x.rbs_email_rangers = ENV["RANGER_CLUBHOUSE_RBS_EMAIL_LIVE"] == "true"

  # All other mail goes by the SMTP settings above until this is switched on
  # for the server; then config/initializers/mail_delivery.rb sends it through
  # Amazon SES instead (SesMailDelivery), with the keys broadcast email uses.
  # Only recorded here: the keys and the app's own code are not loaded yet.
  config.x.ses_mail_live = ENV["RANGER_CLUBHOUSE_SES_MAIL_LIVE"] == "true"

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # Enable DNS rebinding protection and other `Host` header attacks, on a server that
  # names its address. Rails builds request.host, and every *_url, from X-Forwarded-Host
  # when it is present; the nginx in front of Puma (docker/nginx/, and the beta's) overwrites
  # a client's, and this is the backstop behind it.
  if (host = ENV["RANGER_CLUBHOUSE_HOST"].presence)
    config.hosts << host
    # The load balancer's health check sends the task's own IP as Host.
    config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  end

  # request.remote_ip (sessions, the request log, rate_limit) is the visitor because the nginx in
  # front of Puma sets X-Forwarded-For to the one address Cloudflare names, from a loopback peer
  # the default trusted proxies cover. Nothing upstream is trusted here: whatever the AWS load
  # balancer does to X-Forwarded-For (preserve it, or append its peer), nginx overwrites it.
end
