# frozen_string_literal: true

require "active_storage/service/disk_service" # loaded lazily otherwise: absent where files are on S3

# Brings Active Storage files onto this server's disk. A database restored from
# AWS says every file is on S3 (`active_storage_blobs.service_name`); this
# copies each one to the disk service and points its row there. The source is
# only read: nothing on it is deleted or changed.
#
# The disk service keeps a file at root/<key> (FlatDisk), the path it has as an
# S3 object, so a file that is already there under the right checksum is kept
# and nothing is downloaded for it.
#
# A moved row remembers where its file came from in `metadata["localized_from"]`.
# Nothing here moves a row back. The mark tells a file that is still on S3 from
# one uploaded to this disk afterwards, which is on no other service, and it is
# how a marked row's file is fetched again: the database is shared by every
# checkout and storage/ is not, so a row can say this disk where the file is not.
class BlobLocalizer
  # A file left where it is for a reason the message gives. The row is untouched.
  class Skipped < StandardError; end

  BUCKET = "ranger-photos" # production's
  MARK = "localized_from"

  attr_reader :to

  def self.bucket
    ENV["RANGER_CLUBHOUSE_S3_BUCKET"].presence || BUCKET
  end

  # The service of that name, to read from. S3 is built here and not taken from
  # config/storage.yml, which has no bucket on a laptop and must not get one:
  # there, purging a cloned row would ask S3 to delete production's file.
  def self.source(name)
    return ActiveStorage::Blob.services.fetch(name) unless name == "amazon"

    require "active_storage/service/s3_service"
    begin
      ActiveStorage::Service::S3Service.new(bucket:)
    rescue ArgumentError => e # the SDK's error for an `aws login` cache it cannot read
      raise Skipped, "is on S3, and the sign-in could not be read (#{e.message})"
    end
  end

  # `to` is the disk service the files move to. `source` answers the service of
  # a name, and is asked once per name, only when a file must be copied.
  # Raising counts as its answer: a sign-in that fails for one file fails for
  # them all, and is not tried again for each.
  def initialize(to: ActiveStorage::Blob.service, source: ->(name) { self.class.source(name) })
    unless to.is_a?(ActiveStorage::Service::DiskService)
      raise ArgumentError, "This server stores its files on #{to.name}, not on disk"
    end

    @to = to
    @source = source
    @sources = Concurrent::Map.new # fetch runs in threads
  end

  def pending
    ActiveStorage::Blob.where.not(service_name: to.name.to_s)
  end

  # Every blob whose file is another service's: not pointed here yet, or pointed
  # here by an earlier run. The mark is matched as a key of the stored JSON.
  # Quoted by hand: left to Arel, the pattern is cast as the column's value, a
  # JSON hash, and matches nothing.
  def remote
    marked = Arel::Nodes.build_quoted("%\"#{ActiveStorage::Blob.sanitize_sql_like(MARK)}\":%")
    pending.or(ActiveStorage::Blob.where(ActiveStorage::Blob.arel_table[:metadata].matches(marked)))
  end

  # The name of the service a blob's file came from.
  def origin(blob)
    blob.metadata[MARK] || blob.service_name
  end

  # Answers :found when the file was already on disk and :copied when it was
  # fetched. Raises, leaving the row as it was: Skipped, or
  # ActiveStorage::FileNotFoundError or IntegrityError when the source has no
  # such file or the bytes do not match the blob's checksum.
  def localize(blob)
    fetch(blob).tap { point(blob) }
  end

  # The file half of localize. It reads the blob but never the database, so
  # several can run at once in threads.
  def fetch(blob)
    raise Skipped, "has no checksum to check the file against" if blob.checksum.blank?

    on_disk?(blob) ? :found : copy(blob)
  end

  # The row half: only for a blob whose fetch answered. A row already pointed
  # here is left alone, and the mark always names where the file came from. The
  # row is read again first: the blob was loaded before its file was fetched,
  # and what was written to its metadata since must stay.
  def point(blob)
    return if blob.service_name == to.name.to_s

    row = ActiveStorage::Blob.find_by(id: blob.id) or return
    row.update_columns(service_name: to.name.to_s, metadata: row.metadata.merge(MARK => origin(row)))
  end

  private

  def on_disk?(blob)
    to.exist?(blob.key) && OpenSSL::Digest::MD5.file(to.path_for(blob.key)).base64digest == blob.checksum
  end

  # Checked twice: the download against the blob's checksum, then the file as
  # written. A half-written file from an interrupted run is overwritten here.
  def copy(blob)
    source_for(blob).open(blob.key, checksum: blob.checksum) do |file|
      to.upload(blob.key, file, checksum: blob.checksum)
    end
    :copied
  end

  def source_for(blob)
    name = origin(blob)
    source = @sources.compute_if_absent(name) do
      @source.call(name)
    rescue StandardError => e
      e
    end
    raise source if source.is_a?(Exception)

    source
  rescue KeyError
    raise Skipped, "is on #{name}, which config/storage.yml does not define"
  end
end
