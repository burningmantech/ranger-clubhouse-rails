# frozen_string_literal: true

require "test_helper"
require "rake"

# Files move from another storage service to this server's disk, and a blob's
# row follows only once its file is there under the right checksum.
class BlobLocalizerTest < ActiveSupport::TestCase
  include EnvTestHelper

  DATA = "a photo's bytes"

  setup do
    @disk = ActiveStorage::Blob.service
    @keys = []
    @remote_root = Dir.mktmpdir("blob-localizer")
    @remote = ActiveStorage::Service::FlatDiskService.new(root: @remote_root)
    @localizer = BlobLocalizer.new(source: ->(_blob) { @remote })
  end

  teardown do
    @keys.each { |key| @disk.delete(key) } # the rows roll back; the files would stay
    FileUtils.remove_entry(@remote_root)
  end

  test "a file on the other service is copied and its row pointed at the disk" do
    blob = remote_blob("localize/copied.jpg")

    assert_equal :copied, @localizer.localize(blob)

    assert_equal @disk.name.to_s, blob.reload.service_name
    assert_equal DATA, File.binread(@disk.path_for(blob.key))
    assert @remote.exist?(blob.key), "the source keeps its file"
    assert_not_includes @localizer.pending, blob
  end

  test "a moved row remembers the service its file came from, beside what the metadata held" do
    blob = remote_blob("localize/marked.jpg")
    blob.update_columns(metadata: { "identified" => true }) # update! would ask S3 to take the new metadata

    @localizer.localize(blob)

    assert_equal({ "identified" => true, "localized_from" => "amazon" }, blob.reload.metadata)
  end

  test "a file already on disk is kept and nothing is fetched" do
    blob = remote_blob("localize/found.jpg", upload: false)
    @disk.upload(blob.key, StringIO.new(DATA))
    localizer = BlobLocalizer.new(source: ->(_blob) { flunk "the source was asked for a file already on disk" })

    assert_equal :found, localizer.localize(blob)
    assert_equal @disk.name.to_s, blob.reload.service_name
  end

  test "a half-written file on disk is replaced" do
    blob = remote_blob("localize/partial.jpg")
    @disk.upload(blob.key, StringIO.new(DATA[0, 5]))

    assert_equal :copied, @localizer.localize(blob)
    assert_equal DATA, File.binread(@disk.path_for(blob.key))
  end

  test "a file missing from the other service leaves the row alone" do
    blob = remote_blob("localize/missing.jpg", upload: false)

    assert_raises(ActiveStorage::FileNotFoundError) { @localizer.localize(blob) }
    assert_equal "amazon", blob.reload.service_name
    assert_includes @localizer.pending, blob
  end

  test "a file that does not match its checksum leaves the row alone and no file behind" do
    blob = remote_blob("localize/corrupt.jpg", upload: false)
    @remote.upload(blob.key, StringIO.new("other bytes"))

    assert_raises(ActiveStorage::IntegrityError) { @localizer.localize(blob) }
    assert_equal "amazon", blob.reload.service_name
    assert_not @disk.exist?(blob.key)
  end

  test "a blob with no checksum is skipped: nothing could vouch for its file" do
    blob = remote_blob("localize/unchecked.jpg")
    blob.update_columns(checksum: nil)

    error = assert_raises(BlobLocalizer::Skipped) { @localizer.localize(blob) }
    assert_match "no checksum", error.message
    assert_equal "amazon", blob.reload.service_name
    assert_not @disk.exist?(blob.key)
  end

  test "a blob on a service storage.yml does not define is skipped" do
    blob = remote_blob("localize/elsewhere.jpg", service_name: "elsewhere")

    error = assert_raises(BlobLocalizer::Skipped) { BlobLocalizer.new.localize(blob) }
    assert_match "elsewhere", error.message
    assert_equal "elsewhere", blob.reload.service_name
  end

  test "a service that is not a disk is refused" do
    assert_raises(ArgumentError) { BlobLocalizer.new(to: Struct.new(:name).new("amazon")) }
  end

  # The task itself. No S3 here: with no bucket named, a file that would need
  # one is skipped before anything is asked of AWS.

  test "the task moves every file it can, lists the rest by reason and exits 1" do
    needs_s3 = remote_blob("localize/task-needs-s3.jpg", upload: false)
    undefined = remote_blob("localize/task-elsewhere.jpg", upload: false, service_name: "elsewhere")
    on_disk = remote_blob("localize/task-on-disk.jpg", upload: false) # made last: the others come first
    @disk.upload(on_disk.key, StringIO.new(DATA))
    sql_logger = ActiveRecord::Base.logger

    output, status = with_env("RANGER_CLUBHOUSE_S3_BUCKET" => nil) { run_task }

    assert_equal 1, status
    assert_equal @disk.name.to_s, on_disk.reload.service_name
    assert_equal "amazon", needs_s3.reload.service_name
    assert_equal "elsewhere", undefined.reload.service_name
    assert_match "Already on disk: 1. Copied: 0. Failed: 2.", output
    assert_match "1 is not on this disk, and RANGER_CLUBHOUSE_S3_BUCKET is not set: #{needs_s3.key}", output
    assert_match "1 is on elsewhere, which config/storage.yml does not define: #{undefined.key}", output
    assert_same sql_logger, ActiveRecord::Base.logger, "the task puts the loggers back"
  end

  test "the task ends quietly when every file is already on this disk" do
    output, status = run_task

    assert_equal 0, status
    assert_match "Already on disk: 0. Copied: 0. Failed: 0.", output
  end

  private

  # A blob whose row says another service: S3, unless named. update_columns,
  # because the validation would build the real S3 service to check the name.
  def remote_blob(key, upload: true, service_name: "amazon")
    @keys << key
    @disk.delete(key) # keys repeat from run to run
    @remote.upload(key, StringIO.new(DATA)) if upload
    ActiveStorage::Blob.create!(key:, filename: File.basename(key), byte_size: DATA.bytesize,
                                checksum: OpenSSL::Digest::MD5.base64digest(DATA))
                       .tap { |blob| blob.update_columns(service_name:) }
  end

  # Runs storage:localize and answers what it printed and its exit status.
  def run_task
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
    load Rails.root.join("lib/tasks/storage.rake") unless Rake::Task.task_defined?("storage:localize")

    status = 0
    output = capture_io do
      Rake::Task["storage:localize"].tap(&:reenable).invoke
    rescue SystemExit => e
      status = e.status
    end
    [output.join, status]
  end
end
