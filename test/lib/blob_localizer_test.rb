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
    @localizer = BlobLocalizer.new(source: ->(_name) { @remote })
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
    localizer = BlobLocalizer.new(source: ->(_name) { flunk "the source was asked for a file already on disk" })

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

  # Rows an earlier run pointed here: the database is shared by every checkout,
  # and this disk may not be the one the files were copied to.

  test "a row already pointed here gets its file back when this disk has lost it, and keeps its mark" do
    blob = remote_blob("localize/restored.jpg")
    @localizer.localize(blob)
    @disk.delete(blob.key)

    assert_equal :copied, @localizer.localize(blob.reload)

    assert_equal DATA, File.binread(@disk.path_for(blob.key))
    assert_equal @disk.name.to_s, blob.reload.service_name
    assert_equal "amazon", blob.metadata["localized_from"]
  end

  test "the files to have are those on another service or pointed here earlier, not ones uploaded here" do
    waiting = remote_blob("localize/waiting.jpg")
    pointed = remote_blob("localize/pointed.jpg").tap { |blob| @localizer.localize(blob) }
    uploaded = ActiveStorage::Blob.create!(key: "localize/uploaded.jpg", filename: "uploaded.jpg",
                                           byte_size: DATA.bytesize, checksum: OpenSSL::Digest::MD5.base64digest(DATA),
                                           metadata: { "note" => "localized_from", "localizedXfrom" => "amazon" })

    assert_includes @localizer.remote, waiting
    assert_includes @localizer.remote, pointed
    assert_not_includes @localizer.remote, uploaded, "only the mark itself counts, not metadata that looks like it"
  end

  test "a marked row on another disk keeps naming the service its file came from" do
    blob = remote_blob("localize/moved-twice.jpg", service_name: "local")
    blob.update_columns(metadata: { "localized_from" => "amazon" })

    assert_equal :copied, @localizer.localize(blob)

    assert_equal @disk.name.to_s, blob.reload.service_name
    assert_equal "amazon", blob.metadata["localized_from"]
  end

  test "pointing a row keeps what was written to it after it was loaded" do
    blob = remote_blob("localize/cropped.jpg")
    ActiveStorage::Blob.where(id: blob.id).update_all(metadata: { "crop_data" => { "scale_x" => 2 } })

    @localizer.localize(blob)

    assert_equal({ "crop_data" => { "scale_x" => 2 }, "localized_from" => "amazon" }, blob.reload.metadata)
  end

  test "a source that cannot be had is asked for once, and every file gets its reason" do
    asked = 0
    localizer = BlobLocalizer.new(source: lambda do |_name|
      asked += 1
      raise KeyError
    end)

    2.times do |n|
      blob = remote_blob("localize/unsourced-#{n}.jpg")
      assert_raises(BlobLocalizer::Skipped) { localizer.localize(blob) }
    end
    assert_equal 1, asked
  end

  # Built with made-up keys from the environment: nothing is asked of AWS, and no profile or sign-in is read.
  test "the S3 reader is its own, on the bucket; any other name is the service storage.yml defines" do
    with_env("AWS_ACCESS_KEY_ID" => "made-up", "AWS_SECRET_ACCESS_KEY" => "made-up", "AWS_SESSION_TOKEN" => nil,
             "AWS_REGION" => "us-west-2", "AWS_PROFILE" => nil, "RANGER_CLUBHOUSE_S3_BUCKET" => nil) do
      assert_equal "ranger-photos", BlobLocalizer.source("amazon").bucket.name
    end
    assert_same @disk, BlobLocalizer.source(@disk.name.to_s)
  end

  test "S3 files are read from production's bucket unless another is named" do
    with_env("RANGER_CLUBHOUSE_S3_BUCKET" => nil) { assert_equal "ranger-photos", BlobLocalizer.bucket }
    with_env("RANGER_CLUBHOUSE_S3_BUCKET" => "another") { assert_equal "another", BlobLocalizer.bucket }
  end

  # The task itself. No S3 here: run_task has "amazon" answer the folder that
  # stands in for it, so no test can ask anything of AWS.

  test "the task brings every file it can, lists the rest by reason and exits 1" do
    missing = remote_blob("localize/task-missing.jpg", upload: false)
    undefined = remote_blob("localize/task-elsewhere.jpg", upload: false, service_name: "elsewhere")
    copied = remote_blob("localize/task-copied.jpg")
    restored = remote_blob("localize/task-restored.jpg").tap { |blob| @localizer.localize(blob) }
    @disk.delete(restored.key)
    on_disk = remote_blob("localize/task-on-disk.jpg", upload: false) # made last: the others come first
    @disk.upload(on_disk.key, StringIO.new(DATA))
    sql_logger = ActiveRecord::Base.logger
    aws_config = Aws.config

    output, status = run_task

    assert_equal 1, status
    assert_equal @disk.name.to_s, on_disk.reload.service_name
    assert_equal @disk.name.to_s, copied.reload.service_name
    assert @disk.exist?(restored.key), "a row already pointed here has its file again"
    assert_equal "amazon", restored.reload.metadata["localized_from"]
    assert_equal "amazon", missing.reload.service_name
    assert_equal "elsewhere", undefined.reload.service_name
    assert_match "5 files to have on #{@disk.root}. S3 files are read from the bucket #{BlobLocalizer.bucket}.", output
    assert_match "Already on disk: 1. Copied: 2. Failed: 2.", output
    assert_match "1 is not on amazon: #{missing.key}", output
    assert_match "1 is on elsewhere, which config/storage.yml does not define: #{undefined.key}", output
    assert_same sql_logger, ActiveRecord::Base.logger, "the task puts the loggers back"
    assert_same aws_config, Aws.config, "and the SDK's"
  end

  test "the task stops when the sign-in has expired, says how to renew it and asks for it once" do
    blobs = Array.new(12) { |n| remote_blob("localize/task-signed-out-#{n}.jpg", upload: false) }
    asked = 0

    output, status = run_task(amazon: lambda do
      asked += 1
      raise Aws::Errors::InvalidLoginToken, "Please reauthenticate."
    end)

    assert_equal 1, status
    assert_equal 1, asked
    assert_equal ["amazon"], blobs.map { |blob| blob.reload.service_name }.uniq
    assert_match "Stopped at 12/12: 10 files in a row could not be read. `aws login` renews an expired sign-in.", output
    assert_match "12 could not be read (Aws::Errors::InvalidLoginToken: Please reauthenticate.): #{blobs.first.key}", output
  end

  test "the task does not blame the sign-in when S3 cannot be reached" do
    10.times { |n| remote_blob("localize/task-offline-#{n}.jpg", upload: false) }

    output, status = run_task(amazon: -> { raise Seahorse::Client::NetworkingError, SocketError.new("no network") })

    assert_equal 1, status
    assert_match "Stopped at 10/10: 10 files in a row could not be read.\n", output
    assert_no_match(/renews an expired sign-in/, output)
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
  # For as long as the task runs, "amazon" is what `amazon` answers: the stand-in folder, unless a test says.
  def run_task(amazon: -> { @remote })
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
    load Rails.root.join("lib/tasks/storage.rake") unless Rake::Task.task_defined?("storage:localize")
    source = BlobLocalizer.method(:source)
    BlobLocalizer.define_singleton_method(:source) { |name| name == "amazon" ? amazon.call : source.call(name) }

    status = 0
    output = capture_io do
      Rake::Task["storage:localize"].tap(&:reenable).invoke
    rescue SystemExit => e
      status = e.status
    end
    [output.join, status]
  ensure
    BlobLocalizer.define_singleton_method(:source, source) if source
  end
end
