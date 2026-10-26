source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.4", ">= 8.1.4"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use mariadb-mysql as the database for Active Record
gem "mysql2", "~> 0.5"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem "cssbundling-rails"

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# vips is the variant processor (config/application.rb); image_processing is
# declared further down and no longer carries ruby-vips itself, so this stays.
gem "ruby-vips"

gem "argon2"

# Passkey sign-in: checks what a phone, laptop or security key presents (WebAuthn)
gem "webauthn", "~> 3.4"

gem "activerecord-session_store"

gem "tailwindcss-rails", "~> 4.4"

gem "responders"

gem "strip_attributes"

gem "foreman"

gem "phonelib"

gem "twilio-ruby"

gem "text"

gem "twitter_cldr", "~> 6.14"

gem "securerandom", "~> 0.4.1"

gem "validates_timeliness", "~> 8.0.0"

gem "image_processing", "~> 2.1"

gem "rails_autolink"

gem "liquid"

gem "icalendar"

gem "pagy"

gem "user_agent_parser"

gem "aws-sdk-rails"
gem "aws-actionmailer-ses"
# Broadcast email goes straight to SES SendBulkEmail (app/lib/rbs.rb).
gem "aws-sdk-sesv2"
# Active Storage's S3 service (the amazon entry in config/storage.yml) requires it itself.
gem "aws-sdk-s3", require: false

gem "ostruct"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  # gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  #  gem "debase"
  # gem "ruby-debug-ide"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  gem "rubocop", require: false
  gem "rubocop-rails", require: false

  gem "binding_of_caller"

  gem "standard", ">= 1.51.1", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end

gem "naturally", "~> 2.3"

gem "rails-hyperdrive", "~> 0.10.1", group: :development
plugin "bundler-hyperdrive"
