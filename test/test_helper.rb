ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Stub for YearsManagement module used in PersonAward callbacks
module YearsManagement
  class << self
    def update_years_of_awards(person_id)
      # Stub method for tests - does nothing
      # This prevents errors when creating/updating PersonAward records in tests
    end

    def update_timesheet_years(person_id)
      # Stub method for tests - does nothing
    end

    def update_signup_years(person_id)
      # Stub method for tests - does nothing
    end
  end
end

# Load support files
Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

# Message wording lives in the database, so a mailer cannot render without it.
# There is no fixture for it: the templates the Clubhouse ships are the ones the
# tests should be reading, and loading them again is safe.
MailTemplateSeeds.load!

module ActiveSupport
  class TestCase
    # Eight processes, each on its own database (clubhouse3_test_<n>, built from
    # db/schema.rb) and storage root. PARALLEL_WORKERS=1 runs serially, and a run
    # of under 50 tests stays in this process, on clubhouse3_test. CSS_SNAPSHOT
    # runs serially: CssSnapshot gathers rendered templates in this process's
    # memory, which a worker's renders never reach.
    parallelize(workers: CssSnapshot.enabled? ? 1 : 8)

    # A worker's database has none of the seeds loaded above. Blob keys are fixed
    # names (photos/<file>, exports/<file>), so workers sharing tmp/storage
    # overwrite and read each other's files.
    parallelize_setup do |worker|
      MailTemplateSeeds.load!
      ActiveStorage::Blob.service.root = "#{ActiveStorage::Blob.service.root}-#{worker}"
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
