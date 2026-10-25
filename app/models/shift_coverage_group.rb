# frozen_string_literal: true

# One kind of shift the Shift Coverage report can be run for: what the Shift
# Type menu calls it, the slug that rides in ?type= and the export's file name,
# and the positions whose shifts set the report's periods (rows). Its posts are
# the report's columns.
class ShiftCoverageGroup < ApplicationRecord
  include SortIndexLine

  self.table_name = "shift_coverage_group"
  self.audit_model = true

  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  SLUG_LIMIT = 40
  TITLE_LIMIT = 40

  # JSON is LONGTEXT on MariaDB and reads back as a String without this. Not
  # type: Array -- that writes an empty list as NULL, which the column refuses.
  serialize :base_position_ids, coder: JSON

  has_many :shift_coverage_positions, -> { ordered }, dependent: :destroy

  validates :slug, presence: true, uniqueness: true, length: { maximum: SLUG_LIMIT },
                   format: { with: SLUG_FORMAT, allow_blank: true }
  # Unique, because the report's Shift Type menu and heading name a shift type
  # by its title alone.
  validates :title, presence: true, uniqueness: true, length: { maximum: TITLE_LIMIT }
  validate :base_positions_are_positions

  # The shift types whose period positions include the position. Read in Ruby:
  # the list is a JSON column, and there are a dozen rows.
  def self.listing_position(position_id) = all.select { |group| group.base_position_ids.include?(position_id) }

  # Take a deleted position out of every shift type's period positions. A list
  # this empties stays: the shift type draws no rows until an admin chooses a
  # position. validate: false, so a rule against an empty list could never
  # block the delete itself. Only a row that names the position is saved:
  # `changed?` is no test of that, since a row whose JSON is spelled differently
  # from how the app writes it reads as changed on its own.
  def self.remove_position(position_id, reason:)
    listing_position(position_id).each do |group|
      group.audit_reason = reason
      group.base_position_ids -= [position_id]
      group.save!(validate: false)
    end
  end

  # Stored as integers: the report matches them against slot.position_id, and
  # "19" never equals 19. The checkbox list's blank is dropped; anything else
  # that is not an id is kept as sent, so the validation refuses it instead of
  # dropping it silently. Ids already stored keep their places: the boxes post
  # in title order, and rewriting [9, 1] as [1, 9] would log a change nobody
  # made.
  def base_position_ids=(values)
    list = Array(values).reject(&:blank?).map { |value| IdList.id(value) || value }.uniq
    super((Array(base_position_ids) & list) | list)
  end

  # Trimmed, so " Command" cannot pass for a second "Command". A setter rather
  # than normalizes, which would also rewrite where and update_column.
  def title=(value)
    super(StripAttributes.strip(value))
  end

  private

  # The line a shift type is ordered among: every one of them.
  def line_scope = self.class.all

  # Written whole sentences, since errors.format prints a message alone. Inactive
  # positions are fine: several shift types are seeded with one.
  def base_positions_are_positions
    list = Array(base_position_ids)
    return errors.add(:base_position_ids, "Choose at least one period position.") if list.empty?

    ids, junk = list.partition { |value| value.is_a?(Integer) }
    junk.each { |value| errors.add(:base_position_ids, "Period position #{value.inspect} is not a position id.") }
    (ids - Position.where(id: ids).pluck(:id)).each do |id|
      errors.add(:base_position_ids, "Period position ##{id} does not exist.")
    end
  end
end
