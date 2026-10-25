# frozen_string_literal: true

# Every active shift of an event year and how full it is, grouped by position.
#
# Read at two depths: an index of positions with their totals, and one
# position's shifts. Switched-off shifts are left out of both -- no one can sign
# up for one, so it is not a gap anyone can close, and counting it would only
# make the year look emptier than it is.
#
# Sign-ups are counted from the sign-up rows rather than read off slot.signed_up.
# That counter is only bumped by the scheduling write path, so anything writing
# person_slot directly leaves it stale -- and this page links straight to the
# schedule report, which counts the rows. Two pages a click apart disagreeing
# about the same shift is worse than one more grouped count.
class ShiftSignupsReport
  # Filled this thinly and the shift is the report's finding rather than its
  # content. The pages colour a row against it and the list can narrow to it.
  LOW_FILL_PERCENTAGE = 20

  # How full something is. Shared by every level, which each know their own
  # sign-ups and seats.
  module Fill
    # Nil when there are no seats: a shift with no sign-up limit cannot be a
    # fraction of full, and there is nothing to divide by.
    def fill_percentage
      return nil unless seat_count.positive?

      # Integer division, so a part-filled shift rounds down. 99% has to mean
      # "not full yet".
      sign_up_count * 100 / seat_count
    end

    # Thinly covered. Something with no sign-up limit is never low: it has no
    # percentage to be under.
    def low?
      fill = fill_percentage
      !fill.nil? && fill < LOW_FILL_PERCENTAGE
    end
  end

  # One index row: a position and its year.
  Row = Struct.new(:position_id, :title, :shift_count, :seat_count,
                   :sign_up_count, :empty_count) do
    include Fill
  end

  # One shift on the position page.
  Shift = Struct.new(:slot, :sign_up_count) do
    include Fill

    def seat_count = slot.max

    # Counted on the shift's own sign-ups alone. The schedule report next door
    # also credits a shift whose sub-shift is staffed, because it is answering
    # who covers the hour; this page is measuring one shift against its own
    # limit, and crediting people on the numerator who are not on the
    # denominator would leave the two sides describing different things.
    def empty? = sign_up_count.zero?
  end

  # One position's shifts. Every figure is read off the shifts themselves, so
  # the page's totals cannot drift from the rows printed beneath them.
  Detail = Struct.new(:shifts) do
    include Fill

    def shift_count = shifts.size
    def sign_up_count = shifts.sum(&:sign_up_count)
    def seat_count = shifts.sum(&:seat_count)
    def empty_count = shifts.count(&:empty?)
  end

  class << self
    # Every position holding active shifts that year, with its totals, ordered
    # by title.
    def index(year:)
      tallies = shift_tallies(year:)
      return [] if tallies.empty?

      sign_ups = sign_up_tallies(year:)

      # A shift whose position row is gone drops out here. The database has no
      # foreign key to stop that happening, and a position that does not exist
      # cannot be opened anyway.
      Position.where(id: tallies.keys)
              .pluck(:id, :title)
              .map { |id, title|
                shift_count, seat_count = tallies.fetch(id)
                sign_up_count, covered_count = sign_ups.fetch(id, [0, 0])
                Row.new(id, title, shift_count, seat_count, sign_up_count,
                        shift_count - covered_count)
              }
              .sort_by { |row| [row.title.downcase, row.position_id] }
    end

    # One position's active shifts for the year, earliest first, each with its
    # sign-up count.
    #
    # The position is preloaded because the export names it on every row, and
    # asking each shift for it separately is a query per shift.
    def position(year:, position_id:)
      slots = Slot.active.for_year(year).for_position(position_id)
                  .ordered_by_begins.includes(:position).to_a

      Detail.new(shifts_for(slots))
    end

    # Every active shift of the year with its position, for the export. Ordered
    # the way the index lists them: by position title, then earliest first.
    #
    # No order is asked of the database: the sort below settles every row -- the
    # shift's own id breaks any remaining tie -- so sorting twice would only pay
    # for the first one.
    def shifts(year:)
      slots = Slot.active.for_year(year).includes(:position).to_a

      shifts_for(slots).sort_by { |shift|
        [shift.slot.position_title.downcase, shift.slot.begins, shift.slot.id]
      }
    end

    private

    # Pairs the slots with their sign-up counts in one query.
    def shifts_for(slots)
      return [] if slots.empty?

      counts = PersonSlot.where(slot_id: slots.map(&:id)).group(:slot_id).count

      slots.map { |slot| Shift.new(slot, counts.fetch(slot.id, 0)) }
    end

    # How many active shifts each position holds this year, and how many
    # sign-ups they can take between them.
    def shift_tallies(year:)
      Slot.active.for_year(year)
          .group(:position_id)
          .pluck(:position_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(slot.max)"))
          .to_h { |position_id, shift_count, seat_count|
            [position_id, [shift_count, seat_count.to_i]]
          }
    end

    # How many people signed up per position, and how many of that position's
    # shifts have anybody at all. The shifts with no one are the rest of them,
    # which is cheaper to work out than to ask for.
    #
    # The shifts are picked by the same scopes the tally above counts, rather
    # than by a second hand-written copy of them. The two results get subtracted
    # from each other, so a scope that moved on only one side would quietly hand
    # back a position with fewer than no empty shifts.
    def sign_up_tallies(year:)
      PersonSlot.joins(:slot)
                .merge(Slot.active.for_year(year))
                .group("slot.position_id")
                .pluck(Arel.sql("slot.position_id"),
                       Arel.sql("COUNT(*)"),
                       Arel.sql("COUNT(DISTINCT slot.id)"))
                .to_h { |position_id, sign_up_count, covered_count|
                  [position_id, [sign_up_count, covered_count]]
                }
    end
  end
end
