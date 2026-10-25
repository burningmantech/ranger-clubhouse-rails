# frozen_string_literal: true

# Check-ins that landed outside the window around their scheduled shift start
# (Ember reports/early-late-checkins port).
#
# A check-in is flagged when it is more than ShiftCheckInEarlyPeriod before the
# next shift of that position, or more than ShiftCheckInLatePeriod after the one
# already running. Either period set to zero switches its side of the report
# off, as upstream's guards do.
#
# Two rules keep the report honest about how the event actually runs. A position
# with no scheduled shifts around the check-in is ad-hoc and never flagged. And
# a ranger who came off another shift within the hour is forgiven, which is what
# a burn night looks like from here: the perimeter drops, and everyone on it
# goes straight onto Dirt hours after that position's shift began.
#
# Ported from app/Lib/Reports/EarlyLateCheckInReport.php. Upstream compares two
# epoch columns, slot.begins_time against the check-in's own timestamp. This
# compares the datetimes themselves -- see #slots_by_position for why those two
# are not the same question in Rails.
class EarlyLateCheckInReport
  # distance is whole minutes past the limit, rounded up, as upstream reports
  # it. person is nil for a deleted ranger; callsign speaks for both.
  Entry = Data.define(:type, :distance, :person, :person_id, :callsign,
                      :position_id, :position_title, :on_duty, :via,
                      :slot_begins, :slot_description) do
    def early? = type == :early
  end

  PositionTotal = Data.define(:position_id, :title, :total)
  PersonTotal = Data.define(:person, :person_id, :callsign, :total, :positions)

  # early_period and late_period are seconds, and the page says them out loud --
  # a flag means nothing to the reader without the limit it broke, and either one
  # can be zero, which switches that check off rather than tightening it.
  #
  # positions is the whole year's, because it drives the page's own position
  # filter and has to keep offering the positions the reader is not looking at.
  # The rollups on screen are built from whatever survives that filter, so they
  # are the page's to compute -- see person_totals.
  Report = Data.define(:year, :early_period, :late_period, :entries, :positions) do
    def empty? = entries.empty?
  end

  # A check-in made at HQ writes no creation log at all, so its via is nil. The
  # filter and the URL need a name for that case -- a blank one reads as "no
  # filter" rather than "that one". Lives here, the owner of via, so the
  # controller and the helper share it without either reaching into the other.
  VIA_NONE = "none"

  def self.via_param(via) = via.presence || VIA_NONE

  # Too late for the shift running and too early for the next one is a real
  # position for a check-in to be in. Upstream resolves it by which shift the
  # check-in sits nearer to, measured two hours out from each.
  TIEBREAK = 2.hours

  class << self
    def execute(year:)
      early_period, late_period = check_in_periods
      # Both checks off flags nothing, whatever the year holds. Said here rather
      # than discovered one timesheet at a time, which costs the year's slots and
      # timesheets to reach the same empty answer.
      if !early_period.positive? && !late_period.positive?
        return Report.new(year:, early_period:, late_period:, entries: [], positions: [])
      end

      slots = slots_by_position(year)
      timesheets = year_timesheets(year)
      by_person = timesheets.group_by(&:person_id)

      flags = timesheets.filter_map do |timesheet|
        position_slots = slots[timesheet.position_id]
        next if position_slots.blank?

        flag_for(timesheet, position_slots, early_period, late_period, by_person)
      end

      entries = build_entries(flags)

      Report.new(year:, early_period:, late_period:, entries:,
                 positions: position_totals(entries))
    end

    # Worst offenders first, and the same for each ranger's own positions. Ties
    # break on the name so the table does not reshuffle between two readers.
    #
    # Public because the page rolls up whatever is on screen: under a position
    # filter, whole-year totals below a narrowed table would be answering a
    # question no one asked.
    def person_totals(entries)
      entries.group_by(&:person_id).map { |person_id, rows|
        row = rows.first
        PersonTotal.new(person: row.person, person_id:, callsign: row.callsign,
                        total: rows.size, positions: position_totals(rows))
      }.sort_by { |person| [-person.total, person.callsign.downcase] }
    end

    def position_totals(entries)
      entries.group_by(&:position_id).map { |position_id, rows|
        PositionTotal.new(position_id:, title: rows.first.position_title, total: rows.size)
      }.sort_by { |position| [-position.total, position.title.downcase] }
    end

    private

    # The settings are minutes; everything here is seconds.
    def check_in_periods
      values = Setting.get_value([Setting::SHIFT_CHECK_IN_EARLY_PERIOD,
                                  Setting::SHIFT_CHECK_IN_LATE_PERIOD])

      [values[Setting::SHIFT_CHECK_IN_EARLY_PERIOD].to_i * 60,
       values[Setting::SHIFT_CHECK_IN_LATE_PERIOD].to_i * 60]
    end

    # Only shifts a check-in could be measured against: cancelled ones are gone,
    # and a position that keeps no timesheets has no window to be outside of.
    # Ordered by begins so each position's shifts can be searched rather than
    # scanned once per check-in.
    #
    # begins and ends, not the begins_time/ends_time epochs upstream reads. Those
    # columns are written from begins_adjusted, and the two apps disagree about
    # what that means: Laravel shifts the wall clock into the slot's own timezone
    # (America/Los_Angeles by default), Rails only relabels the instant, which
    # leaves it on the app's clock (America/Phoenix). The two agree through the
    # event -- LA is on the same offset as Phoenix in August -- and drift an hour
    # apart off-season. Comparing the datetimes keeps both sides of every
    # comparison on one clock whoever wrote the row.
    def slots_by_position(year)
      Slot.for_year(year)
          .active
          .joins(:position)
          .where(position: { not_timesheet_eligible: false })
          .select(:id, :position_id, :begins, :ends, :description)
          .order(:begins)
          .group_by(&:position_id)
    end

    # Five columns: off_duty is here for the previous-shift rule alone.
    def year_timesheets(year)
      Timesheet.for_year(year)
               .select(:id, :person_id, :position_id, :on_duty, :off_duty)
               .ordered_by_on_duty
               .to_a
    end

    def flag_for(timesheet, slots, early_period, late_period, by_person)
      on_duty = timesheet.on_duty
      # The first shift beginning after the check-in; every shift before it, the
      # check-in is at or past the start of.
      index = slots.bsearch_index { |slot| slot.begins > on_duty }
      upcoming = slots[index] if early_period.positive? && index
      in_progress = running_slot(slots, index, on_duty) if late_period.positive?

      # An ad-hoc position with no set times.
      return if upcoming.nil? && in_progress.nil?

      early = upcoming && on_duty < upcoming.begins - early_period
      late = in_progress && on_duty > in_progress.begins + late_period

      # Made it under the wire.
      return if in_progress && !late
      # Good person, you're not too early.
      return if upcoming && !early
      return if previous_shift?(by_person[timesheet.person_id], on_duty)

      type, slot = pick_shift(early, late, upcoming, in_progress, on_duty)
      [timesheet, type, slot]
    end

    # The latest-beginning shift still running at the check-in. Walking back from
    # the first shift that begins after it visits the same shifts upstream's
    # descending scan does, in the same order, without reading the whole year for
    # every check-in.
    def running_slot(slots, index, on_duty)
      ((index || slots.size) - 1).downto(0) do |cursor|
        slot = slots[cursor]
        return slot if slot.ends >= on_duty
      end

      nil
    end

    # Did the ranger come off another shift within the hour, or are they on one
    # still? Their own check-in is in this list, so a timesheet that ends the
    # moment it starts forgives itself -- upstream's behavior, kept.
    def previous_shift?(timesheets, on_duty)
      hour_before = on_duty - 1.hour

      timesheets.any? do |timesheet|
        off_duty = timesheet.off_duty
        off_duty && off_duty >= hour_before && off_duty <= on_duty
      end
    end

    def pick_shift(early, late, upcoming, in_progress, on_duty)
      return [:early, upcoming] unless late
      return [:late, in_progress] unless early

      # Under two hours into the running shift reads as a late start for it;
      # inside the two hours before the next, as an early start for that one.
      return [:late, in_progress] if on_duty - in_progress.begins < TIEBREAK
      return [:early, upcoming] if on_duty > upcoming.begins - TIEBREAK

      [:late, in_progress]
    end

    # Callsigns, titles and check-in methods for the flagged check-ins alone.
    # Loading them with the year's timesheets would read every ranger and every
    # audit log of the event to name the hundred rows that survive.
    def build_entries(flags)
      timesheets = flags.map(&:first)
      people = Person.where(id: timesheets.map(&:person_id).uniq)
                     .select(:id, :callsign).index_by(&:id)
      titles = Position.titles_by_id(timesheets.map(&:position_id).uniq)
      vias = created_vias(timesheets.map(&:id))

      flags.map do |timesheet, type, slot|
        person = people[timesheet.person_id]
        on_duty = timesheet.on_duty
        distance = type == :late ? on_duty - slot.begins : slot.begins - on_duty

        Entry.new(type:,
                  distance: (distance / 60.0).ceil,
                  person:,
                  person_id: timesheet.person_id,
                  callsign: person&.callsign || "Deleted ##{timesheet.person_id}",
                  position_id: timesheet.position_id,
                  position_title: titles[timesheet.position_id],
                  on_duty:,
                  via: vias[timesheet.id],
                  slot_begins: slot.begins,
                  slot_description: slot.description)
      end
    end

    # A check-in made at HQ writes no creation log at all, which is why a missing
    # id here is not a gap -- it is the ordinary way to start a shift, and the
    # page names it as such.
    # Earliest log wins, as the sibling report's first-of-group does: a timesheet
    # carrying two creation logs must not report a different origin from one read
    # to the next.
    def created_vias(timesheet_ids)
      TimesheetLog.where(timesheet_id: timesheet_ids, action: TimesheetLog::CREATED)
                  .order(:id)
                  .each_with_object({}) do |log, found|
        # key?, not ||=: a first log that records no via is still the log that
        # created this timesheet, and a later one must not speak for it.
        next if found.key?(log.timesheet_id)

        found[log.timesheet_id] = log.data&.dig("via")
      end
    end
  end
end
