# frozen_string_literal: true

namespace :storage do
  desc "Copy files kept on another storage service (S3) to this checkout's disk, and point their records at it"
  task localize: :environment do
    require "aws-sdk-s3" # the app loads it only where files are on S3; its errors are named below

    # A sign-in that has expired, and the command that renews it.
    sign_ins = { Aws::Errors::InvalidLoginToken => "aws login", Aws::Errors::InvalidSSOToken => "aws sso login",
                 Aws::Errors::InvalidSSOCredentials => "aws sso login" }.freeze
    # A file S3 would not give up, for a reason that may pass or may be the whole run's: no
    # credentials, an expired sign-in, no network, no access. S3 also answers a missing file
    # this way (403) to credentials that cannot list the bucket.
    s3_errors = [*sign_ins.keys, Aws::Errors::ServiceError, Aws::Errors::MissingCredentialsError,
                 Aws::Errors::MissingRegionError, Aws::Sigv4::Errors::MissingCredentialsError,
                 Seahorse::Client::NetworkingError].freeze
    give_up_after = 10 # of them in a row
    threads = 8

    localizer = begin
      BlobLocalizer.new
    rescue ArgumentError => e # on AWS: a Fargate task's disk goes with the task
      abort "#{e.message}. Nothing was changed."
    end
    total = localizer.remote.count
    puts "#{total} files to have on #{localizer.to.root}. S3 files are read from the bucket #{BlobLocalizer.bucket}."

    # Development logs to STDOUT: a line per query, per file and per S3 request, the sign-in's
    # own included, would bury everything below.
    loggers = [ActiveRecord::Base, ActiveStorage]
    loggers_were = loggers.map(&:logger)
    loggers.each { |owner| owner.logger = nil }
    aws_config_was = Aws.config
    Aws.config = aws_config_was.except(:logger)

    counts = Hash.new(0)
    failed = Hash.new { |reasons, reason| reasons[reason] = [] }
    done = 0
    s3_error_streak = 0
    renew = nil
    begin
      localizer.remote.find_each.each_slice(threads) do |blobs|
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
          when ActiveStorage::FileNotFoundError then failed["is not on #{localizer.origin(blob)}"] << blob.key
          when ActiveStorage::IntegrityError then failed["does not match its checksum"] << blob.key
          when *s3_errors
            failed["could not be read (#{outcome.class}: #{outcome.message})".truncate(160)] << blob.key
            s3_error = true
            renew = sign_ins[outcome.class]
          else raise outcome
          end
          s3_error_streak = s3_error ? s3_error_streak + 1 : 0
        end

        done += blobs.size
        puts "#{done}/#{total}" if done / 500 > (done - blobs.size) / 500
        if s3_error_streak >= give_up_after
          puts "Stopped at #{done}/#{total}: #{give_up_after} files in a row could not be read." \
               "#{" `#{renew}` renews an expired sign-in." if renew}"
          break
        end
      end
    ensure
      loggers.zip(loggers_were) { |owner, logger| owner.logger = logger }
      Aws.config = aws_config_was
    end

    puts "Already on disk: #{counts[:found]}. Copied: #{counts[:copied]}. Failed: #{failed.values.sum(&:size)}."
    next if failed.empty?

    failed.each do |reason, keys|
      puts "#{keys.size} #{reason}: #{keys.first(5).join(", ")}#{", ..." if keys.size > 5}"
    end
    abort "Those records were left as they were. Run this again once the cause is fixed."
  end
end
