# frozen_string_literal: true

# Every shift of an event year with the people signed up for it, grouped by
# position.
#
# Ported from Laravel's ScheduleByPositionReport. Upstream builds the whole year
# in one payload -- every position, every shift, every sign-up -- and lets the
# browser open one accordion at a time. This port reads it at two depths
# instead: an index of positions, and one position's shifts.
#
# Active and inactive shifts are listed and counted alike. The shift is on the
# board either way, and the position page badges each one, so nothing here has
# to hide it. The one exception is empty_shift_count, which is a call to action
# rather than a count of the board -- see the note on it.
class ScheduleByPositionReport
  # How far apart two shifts can start and still be treated as the same shift
  # running under another position. Upstream's window, kept as-is.
  ASSOCIATED_WINDOW = 1.hour

  # The figures behind one index row.
  Tally = Struct.new(:shift_count, :seat_count, :sign_up_count, :first_begins, :last_ends)

  # One index row.
  Row = Struct.new(:position_id, :title, :position_active, :tally)

  # One shift: the slot, who signed up, and any linked shifts whose sign-ups
  # belong beside it.
  Shift = Struct.new(:slot, :sign_ups, :linked)

  # A shift attached to another one: the parent it feeds, the sub-shift under
  # it, or a shift running alongside under a partner position. `people` is empty
  # both when no one signed up and when there is no such shift at all -- which
  # reads the same either way.
  LinkedShift = Struct.new(:kind, :position_title, :slot_id, :people)

  # A person on a shift. Only the two columns the page prints, rather than whole
  # Person rows: a busy position lists thousands of sign-ups.
  SignUp = Struct.new(:person_id, :callsign)

  # One position's shifts. Every figure is read off the shifts themselves -- a
  # stored count is one more thing that can disagree with the rows beneath it.
  Detail = Struct.new(:shifts) do
    def shift_count = shifts.size
    def sign_up_count = shifts.sum { |shift| shift.sign_ups.size }
    def seat_count = shifts.sum { |shift| shift.slot.max }

    # Shifts no one is covering and somebody still could.
    #
    # Switched-off shifts are left out: no one can sign up for one, so it is not
    # a gap anyone can close. A sub-shift's people count for their parent, the
    # way Scheduling::SlotCapacity folds them everywhere else in the app -- the
    # other two links do not, because a parent's people are not on the sub-shift
    # and a lineup partner has its own seats to fill.
    def empty_shift_count
      shifts.count { |shift| shift.slot.active && uncovered?(shift) }
    end

    private

    def uncovered?(shift)
      shift.sign_ups.empty? &&
        shift.linked.none? { |link| link.kind == :child && link.people.any? }
    end
  end

  class << self
    # Every position holding shifts that year, with its counts, ordered by
    # title the way upstream orders it.
    def index(year:)
      counts = tallies(year:)
      return [] if counts.empty?

      # A shift whose position row is gone drops out here. The schema shared
      # with Laravel carries no foreign keys, and a position that does not exist
      # cannot be opened anyway.
      Position.where(id: counts.keys)
              .pluck(:id, :title, :active)
              .map { |id, title, position_active|
                Row.new(id, title, position_active, counts.fetch(id))
              }
              .sort_by { |row| [row.title.downcase, row.position_id] }
    end

    # One position's shifts for the year, earliest first, each carrying its
    # sign-ups.
    def position(year:, position_id:)
      # The linked slots' positions are preloaded too: naming one costs a query
      # each otherwise, and a position can hold hundreds of linked shifts.
      slots = Slot.includes(parent_signup_slot: :position, child_signup_slot: :position)
                  .for_year(year)
                  .for_position(position_id)
                  .ordered_by_begins
                  .to_a

      Detail.new(shifts_for(slots, position_id))
    end

    private

    # The per-position figures for the year.
    def tallies(year:)
      sign_ups = PersonSlot.joins(:slot)
                           .where(slot: { begins_year: year })
                           .group("slot.position_id")
                           .count

      # in_time_zone is load-bearing. MIN()/MAX() are expressions, so Rails has
      # no column type to cast them with and they arrive in the host's zone,
      # while reading slot.begins casts into Time.zone. For a shift just past
      # midnight the two name different days, and the index would disagree with
      # the page it links to.
      Slot.for_year(year)
          .group(:position_id)
          .pluck(:position_id,
                 Arel.sql("COUNT(*)"), Arel.sql("SUM(slot.max)"),
                 Arel.sql("MIN(slot.begins)"), Arel.sql("MAX(slot.ends)"))
          .to_h { |position_id, shifts, seats, first_begins, last_ends|
            [position_id,
             Tally.new(shifts, seats.to_i, sign_ups.fetch(position_id, 0),
                       first_begins&.in_time_zone, last_ends&.in_time_zone)]
          }
    end

    # Builds the shift list, then fills in every callsign with one query.
    def shifts_for(slots, position_id)
      return [] if slots.empty?

      associated = associated_shifts(slots, position_id)
      shifts = slots.map { |slot| Shift.new(slot, [], linked_shifts(slot, associated)) }

      wanted = shifts.flat_map { |shift| [shift.slot.id] + shift.linked.map(&:slot_id) }
      people = people_by_slot(wanted.compact)

      shifts.each do |shift|
        shift.sign_ups = people.fetch(shift.slot.id, [])
        shift.linked.each { |link| link.people = people.fetch(link.slot_id, []) }
      end
    end

    # The shifts whose sign-ups belong beside this one. A shift has either a
    # parent or a sub-shift, never both -- upstream checks them in that order.
    def linked_shifts(slot, associated)
      parent = slot.parent_signup_slot
      child = slot.child_signup_slot

      links = if parent
                [LinkedShift.new(:parent, parent.position_title, parent.id, [])]
              elsif child
                [LinkedShift.new(:child, child.position_title, child.id, [])]
              else
                []
              end

      links + associated.fetch(slot.id, [])
    end

    # Shifts running alongside these ones under a partner position, from the
    # position lineup: for each shift, the partner's active shift starting
    # within an hour of it.
    #
    # One query for every candidate rather than upstream's one per shift and
    # partner -- a busy position holds hundreds of shifts.
    def associated_shifts(slots, position_id)
      partners = PositionLineup.retrieve_associated_positions(position_id)
      return {} if partners.blank?

      # Bounded by the shifts in hand rather than by the year: a shift an hour
      # either side of New Year is stored under the neighbouring year.
      window = (slots.first.begins - ASSOCIATED_WINDOW)..(slots.last.begins + ASSOCIATED_WINDOW)
      # Filed by partner and by the hour each candidate starts, so looking one
      # up reads three buckets rather than the partner's whole year. Scanning
      # every candidate for every shift was the slowest thing on the page: a
      # position with 500 shifts and 3 partners spent 750,000 comparisons on it.
      candidates = Slot.where(position_id: partners.map(&:id), active: true, begins: window)
                       .pluck(:position_id, :id, :begins)
                       .group_by { |position_id, _id, begins| [position_id, bucket(begins)] }

      slots.to_h do |slot|
        links = partners.map do |partner|
          match = nearest_candidate(candidates, partner.id, slot.begins)
          LinkedShift.new(:associated, partner.title, match, [])
        end

        [slot.id, links]
      end
    end

    # The partner shift closest to this start time, within the window. Upstream
    # takes whichever row the database hands back first; picking the nearest
    # keeps the answer the same on every run.
    def nearest_candidate(candidates, position_id, begins)
      own = bucket(begins)
      nearby = ((own - 1)..(own + 1)).flat_map { |index| candidates.fetch([position_id, index], []) }

      nearby.select { |_position_id, _id, candidate| (candidate - begins).abs <= ASSOCIATED_WINDOW }
            .min_by { |_position_id, id, candidate| [(candidate - begins).abs, id] }
            &.second
    end

    # How many whole windows a start time is from the epoch -- an hours-since-1970
    # count, not a clock hour. Anything within a window of a shift sits in that
    # shift's own bucket or in one of its two neighbours, so those three are the
    # only ones worth reading.
    def bucket(time)
      time.to_i / ASSOCIATED_WINDOW.to_i
    end

    # Everyone signed up for these shifts, by shift, in callsign order.
    def people_by_slot(slot_ids)
      return {} if slot_ids.empty?

      Person.joins(:person_slot)
            .where(person_slot: { slot_id: slot_ids })
            .order(:callsign)
            .pluck("person_slot.slot_id", "person.id", "person.callsign")
            .group_by(&:first)
            .transform_values { |rows| rows.map { |_slot_id, id, callsign| SignUp.new(id, callsign) } }
    end
  end
end
