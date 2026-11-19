# frozen_string_literal: true

namespace :storage do
  desc "Copy files kept on another storage service (S3) to this server's disk, and point their records at it"
  task localize: :environment do
    require "aws-sdk-s3" # the app loads it only where files are on S3; its errors are named below

    # A file S3 would not give up, for a reason that may pass or may be the whole run's: no
    # credentials, no network, no access. S3 also answers a missing file this way (403) to
    # credentials that cannot list the bucket.
    s3_errors = [Aws::Errors::ServiceError, Aws::Errors::MissingCredentialsError, Aws::Errors::MissingRegionError,
                 Aws::Sigv4::Errors::MissingCredentialsError, Seahorse::Client::NetworkingError].freeze
    give_up_after = 10 # of them in a row
    threads = 8

    source = lambda do |blob|
      if blob.service_name == "amazon" && ENV["RANGER_CLUBHOUSE_S3_BUCKET"].blank?
        raise BlobLocalizer::Skipped, "is not on this disk, and RANGER_CLUBHOUSE_S3_BUCKET is not set"
      end
      blob.service
    end

    localizer = begin
      BlobLocalizer.new(source:)
    rescue ArgumentError => e # on AWS: a Fargate task's disk goes with the task
      abort "#{e.message}. Nothing was changed."
    end
    total = localizer.pending.count
    puts "#{total} files to bring to #{localizer.to.root}"

    # Development logs to STDOUT: a line per query and per file would bury everything below.
    loggers = [ActiveRecord::Base, ActiveStorage]
    loggers_were = loggers.map(&:logger)
    loggers.each { |owner| owner.logger = nil }

    counts = Hash.new(0)
    failed = Hash.new { |reasons, reason| reasons[reason] = [] }
    done = 0
    s3_error_streak = 0
    begin
      localizer.pending.find_each.each_slice(threads) do |blobs|
        fetched = blobs.map do |blob|
          Thread.new do
            localizer.fetch(blob)
          rescue StandardError => e
            e
          end
        end.map(&:value)

        blobs.zip(fetched) do |blob, outcome|
          s3_error = false
          case outcome
          when Symbol
            localizer.point(blob)
            counts[outcome] += 1
          when BlobLocalizer::Skipped then failed[outcome.message] << blob.key
          when ActiveStorage::FileNotFoundError then failed["is not on #{blob.service_name}"] << blob.key
          when ActiveStorage::IntegrityError then failed["does not match its checksum"] << blob.key
          when *s3_errors
            failed["could not be read (#{outcome.class}: #{outcome.message})".truncate(160)] << blob.key
            s3_error = true
          else raise outcome
          end
          s3_error_streak = s3_error ? s3_error_streak + 1 : 0
        end

        done += blobs.size
        puts "#{done}/#{total}" if done / 500 > (done - blobs.size) / 500
        if s3_error_streak >= give_up_after
          puts "Stopped at #{done}/#{total}: #{give_up_after} files in a row could not be read."
          break
        end
      end
    ensure
      loggers.zip(loggers_were) { |owner, logger| owner.logger = logger }
    end

    puts "Already on disk: #{counts[:found]}. Copied: #{counts[:copied]}. Failed: #{failed.values.sum(&:size)}."
    next if failed.empty?

    failed.each do |reason, keys|
      puts "#{keys.size} #{reason}: #{keys.first(5).join(", ")}#{", ..." if keys.size > 5}"
    end
    abort "Those records were left as they were. Run this again once the cause is fixed."
  end
end
