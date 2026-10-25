# frozen_string_literal: true

# A line of rows held in the order people meet them, numbered from 1 by
# sort_index. A survey's groups are one such line, and so are the questions
# inside a group, the Shift Coverage report's shift types, and each one's
# posts.
#
# The including model defines `line_scope`: the rows this one is ordered among.
module SortIndexLine
  extend ActiveSupport::Concern

  included do
    # Rows on file skip and repeat numbers, so the id breaks the tie and the
    # order a page shows is the order a move reads.
    scope :ordered, -> { order(:sort_index, :id) }
  end

  # Swap places with the neighbour above or below, then write 1..N over the
  # whole line so the numbers agree with it afterwards. Answers false when the
  # row is already at that end, or the direction is not one of the two.
  #
  # The line is read inside the transaction and held there. Two people
  # reordering the same survey at once would otherwise each work from the line
  # as it was before the other moved, and the second one to write would leave
  # two rows sharing a number -- the very thing renumbering prevents.
  def move(direction)
    transaction do
      line = line_scope.lock.ordered.to_a
      from = line.index { |row| row.id == id }
      next false unless from

      to = case direction.to_s
           when "up" then from - 1
           when "down" then from + 1
           end
      next false unless to&.between?(0, line.size - 1)

      line[from], line[to] = line[to], line[from]
      renumber(line)
      true
    end
  end

  # The number a row joining the end of this line should carry.
  def next_sort_index
    line_scope.maximum(:sort_index).to_i + 1
  end

  private

  # Written straight to the column: renumbering is a positional change, and a
  # full save would re-run every sibling's validations -- so one row another
  # application wrote without a report title would make the whole line
  # unmovable -- and would rewrite settings on rows no one touched.
  def renumber(line)
    line.each_with_index do |row, index|
      row.update_columns(sort_index: index + 1) unless row.sort_index == index + 1
    end
  end
end
