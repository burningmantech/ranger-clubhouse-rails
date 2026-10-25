# frozen_string_literal: true

require "zlib"

# Copies databases about: dumping one to a file, loading a file into one, and
# creating or dropping the temporary databases the copies are built in.
#
# Every command is run as a list of arguments rather than a line of shell text,
# so a database name or file path can never be read as something to run. The
# password is handed over through the environment for the same reason.
class DatabaseDump
  class Error < StandardError; end

  # A database name may only be letters, digits, and the punctuation MySQL
  # allows unquoted. Anything else is refused rather than quoted, since the name
  # is going into a statement that cannot take a placeholder.
  NAME_PATTERN = /\A[A-Za-z0-9_$-]+\z/

  CHUNK_SIZE = 64 * 1024

  class << self
    # Where the application is connected right now.
    def primary_config
      ActiveRecord::Base.connection_db_config.configuration_hash
    end

    # The database a training copy is built from, named by the environment.
    def clone_source_config
      {
        host: ENV.fetch("RANGER_DB_CLONE_FROM_HOST_NAME", "localhost"),
        port: ENV.fetch("RANGER_DB_CLONE_FROM_PORT", "3306"),
        database: ENV.fetch("RANGER_DB_CLONE_FROM_DATABASE_NAME", "rangers-ghd"),
        username: ENV.fetch("RANGER_DB_CLONE_FROM_USER_NAME", "rangers"),
        password: ENV.fetch("RANGER_DB_CLONE_FROM_PASSWORD", "donothing")
      }
    end

    # Write a database, or part of one, to a file.
    #
    # @param to [String] the file to write
    # @param append [Boolean] add to the file instead of replacing it
    # @param ignore_tables [Array<String>] tables to leave out entirely
    # @param tables [Array<String>] only these tables, instead of all of them
    # @param no_data [Boolean] the table definitions without their rows
    # @param where [String] only the rows matching this condition
    def dump(config, to:, append: false, ignore_tables: [], tables: [], no_data: false, where: nil)
      database = database_name(config)
      args = base_args("mysqldump", config)
      args.push("--add-drop-table", "--single-transaction", "--skip-add-locks", "--quick")
      args << "--no-data" if no_data
      args.concat(ignore_tables.map { |table| "--ignore-table=#{database}.#{table}" })
      args << "--where=#{where}" if where
      args << database
      args.concat(tables)

      run(args, config, out: [to.to_s, append ? "a" : "w"])
    end

    # Read a file of statements into a database.
    def load(config, from:)
      run(base_args("mysql", config) << database_name(config), config, in: from.to_s)
    end

    # Read a compressed file of statements into a database, without unpacking it
    # to disk first -- these files run to gigabytes.
    def load_gzip(config, from:)
      args = base_args("mysql", config) << database_name(config)

      begin
        IO.popen(environment(config), args, "wb") do |mysql|
          Zlib::GzipReader.open(from) do |file|
            while (chunk = file.read(CHUNK_SIZE))
              mysql.write(chunk)
            end
          end
        end
      rescue Zlib::Error, SystemCallError => e
        # Part of the file has already gone into the database by now, so the
        # database is half-loaded whatever happens next. Say so plainly.
        raise Error, "#{from} could not be read to the end (#{e.message}). " \
                     "The database is part-loaded and has to be reloaded from a good copy."
      end

      raise Error, "Loading #{from} failed (#{exit_description})" unless $?&.success?
    end

    # Compress a file, leaving the original alone. Written under another name
    # first: a compress that stops half way would otherwise leave something that
    # looks like a finished archive under the name everything else looks for.
    def gzip(source, to:)
      partial = "#{to}.part"
      Zlib::GzipWriter.open(partial) do |gz|
        File.open(source, "rb") { |file| IO.copy_stream(file, gz) }
      end
      File.rename(partial, to)
    rescue StandardError
      File.delete(partial) if File.exist?(partial)
      raise
    end

    # Add a few lines to a file already written.
    def append(file, text)
      File.write(file, text, mode: "a")
    end

    # The tables in a database whose names match a pattern. Used where a set of
    # tables cannot be named in advance, such as the per-year message archives a
    # copy taken before MergePersonMessageArchives ran still has.
    def tables_like(config, pattern)
      unless pattern.match?(/\A[A-Za-z0-9_%]+\z/)
        raise Error, "#{pattern.inspect} is not a usable table pattern"
      end

      args = base_args("mysql", config)
      args.push("-N", "-B", "-e", "SHOW TABLES LIKE '#{pattern}'", database_name(config))
      names = IO.popen(environment(config), args, &:read)
      raise Error, "Reading the table list failed (mysql exited #{$?.exitstatus})" unless $?.success?

      names.split("\n")
    end

    def create_database(name)
      execute_on_server("CREATE DATABASE #{quote_name(name)}")
    end

    # Start the empty database a copy is built in. Refuses to use the database
    # the copy is being made from, which it would otherwise erase.
    def create_working_database(name)
      if name.to_s == primary_config[:database].to_s
        raise Error, "The working database (#{name}) cannot be the database it is built from"
      end

      drop_database(name)
      create_database(name)
      name
    end

    # Check that whoever is running this means to replace everything in the
    # database the application is connected to.
    def confirm_overwrite!(confirmation)
      target = primary_config[:database].to_s
      return true if confirmation.to_s == target

      raise Error, "This replaces everything in #{target}. " \
                   "Run it again with CONFIRM=#{target} if that is what you want."
    end

    def drop_database(name)
      execute_on_server("DROP DATABASE IF EXISTS #{quote_name(name)}")
    end

    # Point the application at another database for the duration of the block.
    # Used to redact and rebuild a copy through the usual models rather than by
    # writing statements by hand.
    def with_database(name)
      previous = ActiveRecord::Base.connection_db_config
      ActiveRecord::Base.establish_connection(primary_config.merge(database: database_name(database: name)))
      yield
    ensure
      ActiveRecord::Base.establish_connection(previous)
    end

    private

    def base_args(command, config)
      args = [command, "-h", config[:host].to_s, "-u", config[:username].to_s]
      args.push("-P", config[:port].to_s) if config[:port].present?
      args
    end

    def environment(config)
      { "MYSQL_PWD" => config[:password].to_s }
    end

    def run(args, config, **redirects)
      begin
        return if system(environment(config), *args, **redirects)
      rescue SystemCallError => e
        # Raised here rather than reported by the command itself when the file
        # it was told to write cannot be opened at all.
        raise Error, "#{args.first} could not be run: #{e.message}"
      end

      raise Error, "#{args.first} failed (#{exit_description})"
    end

    # What became of the last command, in words. A command stopped by a signal
    # has no exit code at all, which reads as a blank if simply printed.
    def exit_description
      status = $?
      return "no exit status" if status.nil?
      return "killed by signal #{status.termsig}" if status.signaled?

      "exited #{status.exitstatus}"
    end

    def database_name(config)
      name = config[:database].to_s
      raise Error, "#{name.inspect} is not a usable database name" unless name.match?(NAME_PATTERN)

      name
    end

    def quote_name(name)
      raise Error, "#{name.inspect} is not a usable database name" unless name.to_s.match?(NAME_PATTERN)

      "`#{name}`"
    end

    def execute_on_server(statement)
      ActiveRecord::Base.connection.execute(statement)
    end
  end
end
