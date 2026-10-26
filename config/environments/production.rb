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

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

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
  # when it is present; beta's nginx overwrites a client's, the AWS load balancer doesn't.
  if (host = ENV["RANGER_CLUBHOUSE_HOST"].presence)
    config.hosts << host
    # The load balancer's health check sends the task's own IP as Host.
    config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  end

  # Cloudflare's IPv4 edge addresses (https://www.cloudflare.com/ips-v4; the IPv4 half of
  # beta/nginx/01-cloudflare.conf). Behind Cloudflare and the IPv4-only AWS load balancer,
  # X-Forwarded-For ends with the edge address, so trusting these ranges is what makes
  # request.remote_ip the visitor: sessions, the request log and rate_limit key on it.
  config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES + %w[
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18
    108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17
    162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
  ].map { IPAddr.new(_1) }
end
