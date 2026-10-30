# frozen_string_literal: true

# Do not audit this model - it is the audit table itself.
class AccessDocumentChange < ApplicationRecord
  self.record_timestamps = false

  # The legacy "changes" column shadows ActiveModel::Dirty#changes, which
  # Rails blocks by default. Dirty tracking is never used on this model, so
  # allow the column accessor to win.
  def self.dangerous_attribute_method?(name)
    name.to_s == "changes" ? false : super
  end

  # Operation constants
  OP_MODIFY = "modify"
  OP_CREATE = "create"
  OP_DELETE = "delete"

  # Associations
  belongs_to :changer_person, class_name: "Person", optional: true

  # Serialize changes as JSON
  serialize :changes, coder: JSON

  # Log changes to an access document
  #
  # @param record [AccessDocument] The access document
  # @param person_id [Integer, nil] The ID of the person making the change
  # @param changes [Hash] The changes to log
  # @param operation [String] The operation type (modify, create, delete)
  # @return [void]
  def self.log(record, person_id, changes, operation = OP_MODIFY)
    changes = changes.except("comments", :comments)
    return if changes.blank?

    create!(
      record_id: record.id,
      operation:,
      changes:,
      changer_person_id: person_id || 0
    )
  end

  # Normalized column diffs for a modify row: [[column, old, new], ...].
  # The serialized changes column carries either the legacy Laravel array
  # shape [[column, old, new], ...] or the hash shape {column => [old, new]};
  # id and comments are never part of the visible diff.
  def diffs
    return [] unless operation == OP_MODIFY

    rows =
      case changes
      when Array then changes
      when Hash then changes.map { |column, (old_value, new_value)| [column, old_value, new_value] }
      else []
      end

    rows.reject { |column, _old, _new| %w[id comments].include?(column.to_s) }
  end
end
