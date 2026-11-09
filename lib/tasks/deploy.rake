# frozen_string_literal: true

namespace :deploy do
  desc "db:migrate as each deploy's migrate container runs it (see DeployMigrationGuard)"
  task migrate: :environment do
    ActiveRecord::Migration.prepend(DeployMigrationGuard)
    DeployMigrationGuard.retrying { Rake::Task["db:migrate"].tap(&:reenable).invoke }
  end
end
