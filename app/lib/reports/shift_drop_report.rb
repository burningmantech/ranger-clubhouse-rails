# frozen_string_literal: true

# Who dropped a shift close to its start (Ember reports/shift-drop port).
#
# A drop is a person-slot-remove ActionLog naming a shift, logged inside that
# shift's own window: [begins - hours, begins]. Whether the ranger removed
# themselves or someone removed them is not recorded on the row and does not
# matter here -- both leave the same hole in the schedule that close to start.
#
# Upstream (app/Lib/ShiftDropReport.php) runs one ActionLog query per shift --
# some 2,400 of them for a year -- each with the slot id interpolated into a raw
# json_extract, and clamps created_at to the report year, which silently loses
# the December removals of an early-January shift. This reads the year's
# removals once and matches them in Ruby, so the window is bounded by the shifts
# themselves and never by the calendar.
class ShiftDropReport
  # The windows offered, as upstream offers them. Anything else is not an error
  # -- a hand-typed ?hours= falls back to the default rather than an error page.
  HOUR_OPTIONS = [1, 6, 12, 24, 36, 48].freeze
  DEFAULT_HOURS = 12

  # Close enough to the start that the shift cannot realistically be backfilled.
  # This is what the index badges, so it is the whole triage signal of the page.
  URGENT_HOURS = 2

  # person and callsign are filled in only by the methods that render people;
  # summary() counts drops and never names anyone.
  #
  # The notice is kept as exact seconds and rounded only where it is shown.
  # Stored pre-rounded to upstream's one decimal, "47 minutes" came back out of
  # the page as "48 min", because 0.783 hours had already become 0.8.
  #
  # starts_at is the instant the shift starts. begins holds the wall clock of the
  # shift's own zone, so that zone is stamped on, as the page's heading prints
  # the shift; read on the app's clock, a New York shift had three hours more
  # notice than it got.
  Drop = Data.define(:slot, :person, :person_id, :callsign, :dropped_at, :starts_at) do
    def seconds_before = starts_at - dropped_at

    # Only meaningful while the window is wider than the threshold: asked for
    # one hour, every drop is inside two, and the flag would say nothing.
    def urgent? = seconds_before <= URGENT_HOURS.hours

    # Upstream's export unit, and all the precision the question carries -- the
    # reader is judging hours of notice.
    def hours_before = (seconds_before / 1.hour.to_f).round(1)
  end

  PositionCount = Data.define(:position_id, :title, :drop_count, :slot_count, :urgent_count)
  Summary = Data.define(:year, :hours, :positions, :drop_count, :slot_count, :total_slot_count)

  SlotDrops = Data.define(:slot, :drops)
  PositionDetail = Data.define(:year, :hours, :position, :slot_drops, :drop_count,
                               :slot_count, :person_count, :total_slot_count)

  class << self
    # The window is a report parameter rather than free input, and both the
    # controller and the views ask what it resolved to, so the rule lives here.
    # to_s first, as setup_year does with the year: a query string can make any
    # param an Array or an ActionController::Parameters, and a bare to_i on
    # either raises rather than falling back, which is the one thing this
    # method exists to guarantee.
    def normalize_hours(hours)
      value = hours.to_s.to_i

      HOUR_OPTIONS.include?(value) ? value : DEFAULT_HOURS
    end

    # Per-position counts for the year. Only positions that lost someone appear:
    # a position no one dropped has nothing to drill into.
    def summary(year:, hours: DEFAULT_HOURS)
      hours = normalize_hours(hours)
      slots = year_slots(year).select(:id, :position_id, :begins, :timezone).to_a
      drops = scan(slots, hours)
      by_position = drops.group_by { |drop| drop.slot.position_id }

      Summary.new(year:, hours:,
                  positions: position_counts(by_position),
                  drop_count: drops.size,
                  slot_count: distinct_slot_count(drops),
                  total_slot_count: slots.size)
    end

    # One position's year, shift by shift. Only the shifts that lost someone get
    # a section; the rest are counted.
    def position(year:, hours: DEFAULT_HOURS, position:)
      hours = normalize_hours(hours)
      slots = year_slots(year).for_position(position.id).ordered_by_begins.to_a
      drops = with_people(scan(slots, hours))
      by_slot = drops.group_by { |drop| drop.slot.id }

      PositionDetail.new(year:, hours:, position:,
                         slot_drops: slot_drops(slots, by_slot),
                         drop_count: drops.size,
                         slot_count: by_slot.size,
                         person_count: drops.map(&:person_id).uniq.size,
                         total_slot_count: slots.size)
    end

    # Every drop of the year with its person named, for the export. The export
    # is whole where the pages are one position at a time.
    def all_drops(year:, hours: DEFAULT_HOURS)
      with_people(scan(year_slots(year).ordered_by_begins.to_a, normalize_hours(hours)))
    end

    private

    # Every active shift of the year. Unlike the flake report there is no
    # "already started" bound: a removal is logged before its shift begins, so a
    # shift starting in an hour that just lost someone is exactly the row this
    # report exists to show.
    def year_slots(year) = Slot.for_year(year).active

    # One query for the whole report. The removals of a year number in the
    # thousands and carry a JSON blob no index can reach, so the slot match and
    # the window test both happen here rather than in SQL.
    def scan(slots, hours)
      return [] if slots.empty?

      window = hours.hours
      slots_by_id = slots.index_by(&:id)
      starts = slots.to_h { |slot| [slot.id, slot.begins.change(zone: slot.timezone)] }
      logs = removal_logs(starts.values.min - window, starts.values.max)

      logs.filter_map { |log|
        slot = slots_by_id[logged_slot_id(log)]
        starts_at = starts[slot&.id]
        next unless slot && log.created_at >= starts_at - window && log.created_at <= starts_at

        Drop.new(slot:, person: nil, person_id: log.target_person_id, callsign: nil,
                 dropped_at: log.created_at, starts_at:)
      }
    end

    def removal_logs(from, to)
      ActionLog.where(event: "person-slot-remove")
               .where(created_at: from..to)
               .select(:id, :target_person_id, :data, :created_at)
               .to_a
    end

    # ActionLog.slot_id_from_data carries the coercion: the Laravel writers pass
    # the id straight through from a request parameter, so it lands in the JSON
    # as a string often enough that an untyped hash lookup would quietly miss
    # those rows. A row with no usable slot resolves to 0 and matches nothing --
    # one malformed row must not take the whole year's report down with it.
    def logged_slot_id(log) = ActionLog.slot_id_from_data(log.data)

    # One narrow query for the people actually rendered. Person is the widest
    # table in the schema, so it is never preloaded through the association.
    def with_people(drops)
      people = Person.where(id: drops.map(&:person_id).uniq).select(:id, :callsign).index_by(&:id)

      drops.map { |drop|
        person = people[drop.person_id]
        drop.with(person:, callsign: person&.callsign || "Deleted ##{drop.person_id}")
      }
    end

    def position_counts(by_position)
      titles = Position.titles_by_id(by_position.keys)

      by_position.map { |position_id, drops|
        PositionCount.new(position_id:, title: titles[position_id],
                          drop_count: drops.size,
                          slot_count: distinct_slot_count(drops),
                          urgent_count: drops.count(&:urgent?))
      }.sort_by { |position| position.title.downcase }
    end

    # Shift order, and within a shift the order they left in -- the last name on
    # a shift is the one that had the least chance of being replaced.
    def slot_drops(slots, by_slot)
      slots.filter_map { |slot|
        drops = by_slot[slot.id]
        next unless drops

        SlotDrops.new(slot:, drops: drops.sort_by { |drop| [drop.dropped_at, drop.callsign.downcase] })
      }
    end

    def distinct_slot_count(drops) = drops.map { |drop| drop.slot.id }.uniq.size
  end
end
