# frozen_string_literal: true

namespace :clubhouse do
  desc "Delete stored settings the Clubhouse no longer defines"
  task purge_settings: :environment do
    names = Setting.purge_undefined!
    if names.empty?
      puts "Every stored setting is still in use."
    else
      names.each { |name| puts "Deleted #{name}" }
      puts "Deleted #{names.size} #{'setting'.pluralize(names.size)}."
    end
  end

  desc "Delete the badge export archives for a year (defaults to this year)"
  task :delete_bmid_exports, [:year] => :environment do |_task, args|
    year = (args[:year] || Current.year).to_i
    count = BmidExport.delete_all_for_year(year)
    puts "Deleted #{count} badge #{'export'.pluralize(count)} from #{year}."
  end

  desc "Delete every badge export archive, for cleanup once the event is over"
  task delete_bmid_exports_post_event: :environment do
    count = BmidExport.delete_all_for_post_event
    puts "Deleted #{count} badge #{'export'.pluralize(count)}."
  end
end

# Shared pieces for the tasks that copy the database about.
module ClubhouseDatabaseTasks
  module_function

  # Everything except the logs and the message archives: they are the largest
  # tables by far, and a copy has no use for them. The sign-up history is kept,
  # because the schedule pages are built from it.
  KEPT_LOG_EVENTS = "event in ('person-slot-add', 'person-slot-remove')"

  # Turning the checks off while a whole database loads takes hours off it.
  LOAD_FASTER = <<~SQL
    SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, AUTOCOMMIT = 0;
    SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS = 0;
    SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS = 0;
  SQL

  LOAD_DONE = <<~SQL
    SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
    SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
    SET AUTOCOMMIT=@OLD_AUTOCOMMIT;
    COMMIT;
  SQL

  # A database to copy, minus the logs, plus the table definitions the logs need
  # to exist at all and the sign-up history.
  def dump_without_logs(config, file)
    skipped = skipped_logs(config)
    DatabaseDump.dump(config, to: file, append: true, ignore_tables: skipped + ["action_logs"])
    DatabaseDump.dump(config, to: file, append: true, no_data: true, tables: skipped)
    DatabaseDump.dump(config, to: file, append: true, tables: ["action_logs"], where: KEPT_LOG_EVENTS)
  end

  # A copy taken before MergePersonMessageArchives ran still keeps messages in a
  # table per year as well, so the prefix is matched rather than the one table named.
  def skipped_logs(config)
    %w[legacy_log log mail_log] + DatabaseDump.tables_like(config, "person_message%")
  end

  # Six in the evening on the Saturday of last year's burn.
  def last_burn_night
    labor_day = EventDate.first_monday_of_september(Time.zone.today.year - 1)
    (labor_day - 2.days).change(hour: 18)
  end

  def source_config
    DatabaseDump.primary_config
  end

  def announce(message)
    puts message
  end

  # Said out loud when a run stops part way through. Until the personal detail
  # has been taken out, the working database is a copy of the real one, and
  # no one would otherwise know it had been left behind.
  def leftover_warning(working, source)
    "The working database #{working} was left in place. Until this finishes it holds " \
      "everything #{source[:database]} holds, so delete it or run this again."
  end

  # The same warning for the task that replaces the database it is run against.
  # There is no working copy to delete here: the personal detail is in the
  # database the Clubhouse is about to serve from.
  def unfinished_warning(target, source)
    "#{target[:database]} now holds a copy of #{source[:database]} that has NOT been " \
      "redacted. Do not let anybody near it until this has been run again to the end."
  end

  # A copy that reads from the database it writes to destroys the only thing it
  # could be rebuilt from.
  def refuse_to_copy_onto_itself(source, target)
    return unless source[:database].to_s == target[:database].to_s &&
                  source[:host].to_s == target[:host].to_s

    raise DatabaseDump::Error,
          "The database being copied from (#{source[:database]}) is the one being replaced. " \
          "Point RANGER_DB_CLONE_FROM_DATABASE_NAME at the database to copy from."
  end
end

namespace :clubhouse do
  desc "Build a redacted copy of this database and write it to a file"
  task redact_db: :environment do
    working = ENV.fetch("TEMPDB", "rangers_redacted_temp")
    dump_file = ENV.fetch("DUMPFILE", "rangers-redacted-#{Time.zone.today.strftime('%Y-%m-%d')}.sql")
    super_redact = ENV["SUPER_REDACT"].present?
    source = ClubhouseDatabaseTasks.source_config
    copy = File.join(File.dirname(dump_file), "redact-clone-dump.sql")

    begin
      DatabaseDump.create_working_database(working)
      ClubhouseDatabaseTasks.announce("Copying #{source[:database]} into #{working}")
      File.delete(copy) if File.exist?(copy)
      ClubhouseDatabaseTasks.dump_without_logs(source, copy)
      DatabaseDump.load(source.merge(database: working), from: copy)
      File.delete(copy)

      ClubhouseDatabaseTasks.announce("Taking out the personal detail")
      DatabaseDump.with_database(working) { RedactDatabase.execute(super_redact:) }

      ClubhouseDatabaseTasks.announce("Writing #{dump_file}")
      DatabaseDump.dump(source.merge(database: working), to: dump_file)
      DatabaseDump.drop_database(working)
      ClubhouseDatabaseTasks.announce("Done. #{dump_file} holds a redacted copy.")
    rescue DatabaseDump::Error => e
      abort "#{e.message}\n#{ClubhouseDatabaseTasks.leftover_warning(working, source)}"
    rescue StandardError
      warn ClubhouseDatabaseTasks.leftover_warning(working, source)
      raise
    end
  end

  desc "Build a training copy of this database, held at one moment during the event"
  task groundhog_day: :environment do
    working = ENV.fetch("TEMPDB", "rangers_ghd")
    source = ClubhouseDatabaseTasks.source_config

    begin
      moment = if ENV["GHD_DAY"].present?
                 GroundHogDay.parse_moment(ENV["GHD_DAY"])
               else
                 ClubhouseDatabaseTasks.last_burn_night
               end
      dump_file = ENV.fetch("DUMPFILE", "rangers-ghd-#{moment.strftime('%Y-%m-%d')}.sql")
      copy = File.join(File.dirname(dump_file), "ghd-clone-dump.sql")

      DatabaseDump.create_working_database(working)
      ClubhouseDatabaseTasks.announce("Copying #{source[:database]} into #{working} for #{moment}")
      File.delete(copy) if File.exist?(copy)
      ClubhouseDatabaseTasks.dump_without_logs(source, copy)
      DatabaseDump.load(source.merge(database: working), from: copy)
      File.delete(copy)

      DatabaseDump.with_database(working) do
        if ENV["NO_REDACT"].present?
          ClubhouseDatabaseTasks.announce("Leaving the personal detail in place")
        else
          ClubhouseDatabaseTasks.announce("Taking out the personal detail")
          RedactDatabase.execute
        end

        ClubhouseDatabaseTasks.announce("Winding the database back to #{moment}")
        GroundHogDay.build(moment)
      end

      ClubhouseDatabaseTasks.announce("Writing #{dump_file}")
      DatabaseDump.dump(source.merge(database: working), to: dump_file)
      DatabaseDump.drop_database(working)
      ClubhouseDatabaseTasks.announce("Done. #{dump_file} holds a training copy.")
    rescue DatabaseDump::Error => e
      abort "#{e.message}\n#{ClubhouseDatabaseTasks.leftover_warning(working, source)}"
    rescue StandardError
      warn ClubhouseDatabaseTasks.leftover_warning(working, source)
      raise
    end
  end

  desc "Replace this database with a training copy built from the clone source, and write it to a file"
  task create_training_db: :environment do
    moment = ENV[GroundHogDay::ENVIRONMENT_VAR]
    abort "#{GroundHogDay::ENVIRONMENT_VAR} is not set, so there is no moment to hold at." if moment.blank?

    source = DatabaseDump.clone_source_config
    target = ClubhouseDatabaseTasks.source_config
    copy = "clone-dump.sql"

    begin
      DatabaseDump.confirm_overwrite!(ENV["CONFIRM"])
      ClubhouseDatabaseTasks.refuse_to_copy_onto_itself(source, target)
      # Worked out before anything is replaced. A day that cannot be read would
      # otherwise be found only after the database had already been written
      # over, leaving nothing to put back.
      moment = GroundHogDay.parse_moment(moment)
      dump_file = Rails.root.join(GroundHogDay.training_database_dump_name(moment))

      ClubhouseDatabaseTasks.announce("Copying #{source[:database]} into #{target[:database]}")
      File.write(copy, ClubhouseDatabaseTasks::LOAD_FASTER)
      ClubhouseDatabaseTasks.dump_without_logs(source, copy)
      DatabaseDump.append(copy, ClubhouseDatabaseTasks::LOAD_DONE)
      DatabaseDump.load(target, from: copy)
      File.delete(copy)

      ClubhouseDatabaseTasks.announce("Taking out the personal detail")
      RedactDatabase.execute

      ClubhouseDatabaseTasks.announce("Winding the database back to #{moment}")
      GroundHogDay.build(moment)
      GroundHogDay.train_actives(moment.year)

      plain = Rails.root.join("training-dump.sql")
      ClubhouseDatabaseTasks.announce("Writing #{dump_file}")
      DatabaseDump.dump(target, to: plain)
      DatabaseDump.gzip(plain, to: dump_file)
      File.delete(plain)
      ClubhouseDatabaseTasks.announce("Done. #{target[:database]} is a training database, saved as #{dump_file}.")
    rescue DatabaseDump::Error => e
      abort "#{e.message}\n#{ClubhouseDatabaseTasks.unfinished_warning(target, source)}"
    rescue StandardError
      warn ClubhouseDatabaseTasks.unfinished_warning(target, source)
      raise
    ensure
      File.delete(copy) if File.exist?(copy)
    end
  end

  desc "Put the training database back to the start of the day"
  task reload_training_db: :environment do
    DatabaseDump.confirm_overwrite!(ENV["CONFIRM"])
    file = GroundHogDay.reload_training_database!
    puts "Reloaded from #{file}. The cycle of time begins again."
  rescue DatabaseDump::Error => e
    abort e.message
  end
end
