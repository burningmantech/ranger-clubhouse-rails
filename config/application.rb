require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Clubhouse3
  class Application < Rails::Application
    # Use the responders controller from the responders gem
    config.app_generators.scaffold_controller :responders_controller

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_paths << "app/forms"
    config.autoload_paths << "app/lib/reports"
    # lib/middleware is required by hand below: the middleware stack is built
    # while the app boots, and a constant that is autoloaded cannot be named
    # that early.
    config.autoload_lib(ignore: %w[assets tasks middleware])

    require_relative "../lib/middleware/request_logger"
    # Appended, so it runs closest to the application and can still read the
    # signed-in person off Current.
    config.middleware.use RequestLogger

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    config.session_store :active_record_store

    config.time_zone = "America/Phoenix"
    config.active_record.default_timezone = :local

    config.active_storage.variant_processor = :vips

    # Whether broadcast email may go to each Ranger's own address. Off here, so
    # any environment that does not say otherwise holds it back -- a dev copy of
    # the database is full of real people. See Rbs.email_mode.
    config.x.rbs_email_rangers = false

    # Whether all other mail goes out through Amazon SES. Off here for the same
    # reason; only production can turn it on. See SesMailDelivery.install!.
    config.x.ses_mail_live = false
  end
end
