# frozen_string_literal: true

# One Eventree export batch: which people went to the badge printer, who sent
# them, and the CSV exactly as it was downloaded. The file is kept because it
# cannot be rebuilt after the fact -- exporting consumes the provisions and
# flips the badge statuses the rows were derived from.
#
# The table predates this model (Laravel App\Models\BmidExport writes the same
# rows); person_ids is the JSON array both sides store. Rows imported from the
# Laravel era have a filename but no attached file -- their archives live on
# the old export store.
class BmidExport < ApplicationRecord
  self.table_name = "bmid_export"

  # What the batch-information field accepts, upstream parity. The export page
  # caps its input at this and the controller truncates to match.
  BATCH_INFO_LIMIT = 32

  # The person who ran the export, not a subject of it.
  belongs_to :person

  has_one_attached :csv_file
  attachment_key(:csv_file) { |blob| "exports/#{blob.filename}" }

  serialize :person_ids, coder: JSON

  # The column is NOT NULL; an empty batch note is stored as an empty string,
  # upstream parity.
  attribute :batch_info, :string, default: ""

  scope :for_year, ->(year) { where_year("created_at", year) }

  class << self
    # Delete one year's export archives. The stored CSV goes with each record.
    #
    # @return [Integer] how many archives were removed
    def delete_all_for_year(year)
      destroy_each(for_year(year))
    end

    # Delete every export archive, for the cleanup that runs once the event is
    # over and no batch can still be reprinted.
    #
    # @return [Integer] how many archives were removed
    def delete_all_for_post_event
      destroy_each(all)
    end

    private

    # One at a time rather than in bulk, so each record's attached file is
    # removed as well.
    def destroy_each(scope)
      count = 0
      scope.find_each do |export|
        export.destroy!
        count += 1
      end
      count
    end
  end
end
