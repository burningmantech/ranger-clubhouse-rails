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
# Nothing here moves a row back; the mark is what tells a file that is still on
# S3 from one uploaded to this disk afterwards, which is on no other service.
class BlobLocalizer
  # A file left where it is for a reason the message gives. The row is untouched.
  class Skipped < StandardError; end

  attr_reader :to

  # `to` is the disk service the files move to. `source` answers the service a
  # blob's file is read from, and is asked only when the file must be copied.
  def initialize(to: ActiveStorage::Blob.service, source: ->(blob) { blob.service })
    unless to.is_a?(ActiveStorage::Service::DiskService)
      raise ArgumentError, "This server stores its files on #{to.name}, not on disk"
    end

    @to = to
    @source = source
  end

  def pending
    ActiveStorage::Blob.where.not(service_name: to.name.to_s)
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

  # The row half: only for a blob whose fetch answered.
  def point(blob)
    blob.update_columns(service_name: to.name.to_s,
                        metadata: blob.metadata.merge("localized_from" => blob.service_name))
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
    @source.call(blob)
  rescue KeyError
    raise Skipped, "is on #{blob.service_name}, which config/storage.yml does not define"
  end
end
