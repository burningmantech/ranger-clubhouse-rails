# frozen_string_literal: true

require_relative "env_test_helper"

# config/recurring.yml as Solid Queue reads it, rendered for one deployment:
# its label (RANGER_CLUBHOUSE_ENVIRONMENT) and, on the training server, its
# frozen time. Every Rails environment's section comes back, keyed by name.
module RecurringScheduleTestHelper
  include EnvTestHelper

  def recurring_schedule(environment: nil, ghd: nil)
    with_env("RANGER_CLUBHOUSE_ENVIRONMENT" => environment, "RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME" => ghd) do
      ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml"))
    end
  end
end
