# frozen_string_literal: true

# A title that can be printed on a badge, and the position that earns it.
#
# Replaces the upstream Laravel constant App\Models\Bmid::BADGE_TITLES with a
# table, so the list can be maintained without a deploy. Each row maps one
# position to one of the badge's three title lines. When someone holds several
# positions feeding the same line, the lowest sort_index wins -- upstream had
# no tie-breaker at all.
class BmidTitle < ApplicationRecord
  self.table_name = "bmid_title"

  # Who changed the title list is the same question as who changed a title, and
  # Bmid answers it.
  self.audit_model = true

  # The three lines printed on a badge: bmid.title1, title2, and title3.
  TITLE_LINES = [1, 2, 3].freeze

  TITLE_LIMIT = 64

  MOVE_UP = "up"
  MOVE_DOWN = "down"
  MOVE_DIRECTIONS = [MOVE_UP, MOVE_DOWN].freeze

  belongs_to :position

  validates :title, presence: true, length: { maximum: TITLE_LIMIT }
  validates :title_line, inclusion: { in: TITLE_LINES, message: "Title line must be 1, 2, or 3." }
  validates :sort_index, numericality: { only_integer: true }
  validates :position_id, uniqueness: { scope: :title_line,
                                        message: "This position already earns a title on this line." }

  scope :ordered, -> { order(:title_line, :sort_index, :title) }

  # The bmid column this title prints in.
  def bmid_column = "title#{title_line}"

  # Step this title one place up or down its line's order of preference.
  #
  # The line is renumbered rather than two sort_index values swapped: equal
  # numbers and gaps are both legal here, and swapping equal ones would move
  # nothing at all. Only the rows whose number actually changes are written, so
  # a move leaves two audit entries rather than one per title on the line.
  #
  # @param direction [String] MOVE_UP or MOVE_DOWN
  # @return [Boolean] false when the title is already at that end of the line
  def move!(direction)
    line = self.class.where(title_line:).ordered.to_a
    from = line.index { |title| title.id == id }
    to = direction == MOVE_UP ? from - 1 : from + 1
    return false if to.negative? || to >= line.size

    line.insert(to, line.delete_at(from))

    transaction do
      line.each_with_index do |title, index|
        title.update!(sort_index: index + 1) unless title.sort_index == index + 1
      end
    end

    true
  end
end
