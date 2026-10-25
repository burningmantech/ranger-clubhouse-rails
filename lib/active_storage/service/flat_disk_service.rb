# frozen_string_literal: true

require "active_storage/service/disk_service"

# The Disk service, minus the ab/cd/ sharding folders it puts in front of every
# key. Keys here are already paths (photos/<file>, exports/<file>), so the file
# lands at exactly root/<key>, the way it would as an S3 object.
class ActiveStorage::Service::FlatDiskService < ActiveStorage::Service::DiskService
  private

  def folder_for(_key)
    ""
  end
end
