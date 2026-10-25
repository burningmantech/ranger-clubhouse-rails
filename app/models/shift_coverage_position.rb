# frozen_string_literal: true

# One post -- one column of the Shift Coverage report: the positions it reads,
# and whether it names the people on them or only counts them.
#
# position_ids holds [position_id] or [position_id, label] entries, not bare
# ids. The label is printed after the callsign of anyone on that position, so
# one post can carry a position and its junior version without hiding which
# is which. Read it through position_id_list and labels_by_position.
class ShiftCoveragePosition < ApplicationRecord
  include SortIndexLine

  self.table_name = "shift_coverage_position"
  self.audit_model = true

  TITLE_LIMIT = 20
  LABEL_LIMIT = 20

  serialize :position_ids, coder: JSON

  belongs_to :shift_coverage_group

  validates :title, presence: true, length: { maximum: TITLE_LIMIT },
                    uniqueness: { scope: :shift_coverage_group_id }
  validates :count_only, inclusion: { in: [true, false] }
  validate :entries_are_positions

  # The form's rows, paired: each row is a position select and a label field,
  # which always submit together, so the two lists line up. A row with neither
  # is dropped; a label with no position is kept so the validation names it.
  def self.entries_from_rows(ids, labels)
    Array(ids).zip(Array(labels)).filter_map do |id, label|
      label = label.to_s.strip.presence
      next if id.blank? && label.nil?

      [IdList.id(id) || id.to_s, label].compact
    end
  end

  # The posts that read the position, found in Ruby as the shift types are.
  def self.listing_position(position_id) = all.select { |post| post.position_id_list.include?(position_id) }

  # Take a deleted position out of every post that reads it, label and all. A
  # list this empties stays: the post reads nothing until an admin chooses a
  # position. See ShiftCoverageGroup.remove_position for why only the rows that
  # name it are saved, and without validation.
  def self.remove_position(position_id, reason:)
    listing_position(position_id).each do |post|
      post.audit_reason = reason
      post.position_ids = post.position_ids.reject { |id, _label| id == position_id }
      post.save!(validate: false)
    end
  end

  # The positions alone, in order: what the report reads shifts by.
  def position_id_list = position_ids.map(&:first)

  # The label to print after a callsign, by the position the shift is under.
  def labels_by_position = position_ids.to_h { |id, label| [id, label] }.compact

  # Trimmed, so " OOD" cannot pass for a second "OOD": the title is the column
  # heading. A setter rather than normalizes, as on ShiftCoverageGroup.
  def title=(value)
    super(StripAttributes.strip(value))
  end

  private

  # The line a post is ordered among: the posts of its own shift type.
  def line_scope = self.class.where(shift_coverage_group_id:)

  # Written whole sentences, since errors.format prints a message alone. Each
  # names its entry by row:, the index it came in at, so the form can mark that
  # row's controls. Inactive positions are fine: several posts are seeded with
  # one.
  def entries_are_positions
    entries = Array(position_ids)
    return errors.add(:position_ids, "Choose at least one position for the post.") if entries.empty?

    titles = Position.where(id: entries.filter_map { |id, _label| id if id.is_a?(Integer) }).pluck(:id, :title).to_h
    seen = Set.new

    entries.each_with_index do |entry, row|
      message = entry_problem(entry, titles, seen)
      errors.add(:position_ids, message, row:) if message
    end
  end

  # What is wrong with one entry, or nil. seen collects the ids of the entries
  # before it that passed this far.
  def entry_problem(entry, titles, seen)
    return "Position #{entry.inspect} is not a position id." unless entry.is_a?(Array) && entry.size.between?(1, 2)

    id, label = entry
    return "The label #{label.inspect} needs a position beside it." if id == "" && label.present?
    return "Position #{id.inspect} is not a position id." unless id.is_a?(Integer)
    return "Position ##{id} does not exist." unless titles.key?(id)
    return "#{titles[id]} is listed twice. List each position once." unless seen.add?(id)

    return unless label.to_s.length > LABEL_LIMIT

    "The label #{label.to_s.truncate(LABEL_LIMIT + 5).inspect} is too long. Use #{LABEL_LIMIT} characters or fewer."
  end
end
