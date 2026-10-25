# frozen_string_literal: true

# The one question the shift reports share: given a sign-up, was the person
# actually on duty for that position while the shift ran?
#
# The flake report and the no-shows report both turn on it, and they must not
# be able to answer it differently -- so the rule, the bounded query that feeds
# it, and the slot scope it runs over live here rather than in either report.
#
# Included into the reports' singleton classes (`class << self`); every method
# is private there, as it was when this lived on FlakeReport alone.
module ShiftAttendance
  # How far before the shift a CLOSED timesheet's on_duty may reach. The
  # off_duty bound already decides whether it overlaps; this only keeps the
  # scan off the whole table -- without it the range on (person_id, on_duty)
  # is open-ended and every flake's entire career is read to serve one shift.
  MAX_SHIFT_LOOKBACK = 14.days

  private

  # Training positions are out of scope entirely -- trainer slots included, by
  # decree. Attendance at a session is recorded on trainee_status rather than
  # as a timesheet, so the whole type is outside what these reports can audit.
  # Positions no one can go on duty for are excluded too: ShiftManage refuses
  # check-in on them (:position_not_eligible), so their sign-ups could never
  # clear and every one would be reported as a miss.
  #
  # Shifts that have not started yet are out of scope: the reports ask who
  # failed to show, and no one has failed to show for a shift that has not
  # begun. Without this the current year -- the default view -- reports its
  # whole future schedule.
  def scanned_slots(year)
    Slot.for_year(year)
        .active
        .where(begins: ..Current.time)
        .where.not(position_id: excluded_positions.select(:id))
  end

  def excluded_positions
    Position.where(not_timesheet_eligible: true)
            .or(Position.where(type: Position::TYPE_TRAINING))
  end

  # The one place the "did they actually ranger it" rule lives, so no two pages
  # -- or two reports -- can answer it differently. Given (slot_id, person_id)
  # sign-up pairs, drop the ones whose person holds a timesheet in the shift's
  # OWN position overlapping it: the shift was rangered. A timesheet for
  # another position is left in place -- that shift still went uncovered.
  def without_honored_shifts(pairs, slots_by_id)
    return pairs if pairs.empty?

    sheets = own_position_timesheets(pairs, slots_by_id)

    pairs.reject { |slot_id, person_id|
      slot = slots_by_id[slot_id]
      sheets.fetch([person_id, slot.position_id], []).any? { |sheet| covers?(sheet, slot) }
    }
  end

  # One query for the whole page or year: every timesheet the sign-ups hold in
  # the positions they signed up for, over the span those shifts cover.
  def own_position_timesheets(pairs, slots_by_id)
    slots = pairs.map { |slot_id, _| slots_by_id[slot_id] }

    timesheet_window(pairs.map(&:last).uniq,
                     slots.map(&:begins).min, slots.map(&:ends).max)
      .where(position_id: slots.map(&:position_id).uniq)
      .group_by { |sheet| [sheet.person_id, sheet.position_id] }
  end

  # Timesheets that can overlap a span: closed ones have to reach into it,
  # open ones have to start inside it (read as running to now, a sign-on
  # no one closed would otherwise cover every later shift).
  def timesheet_window(person_ids, span_begins, span_ends)
    base = Timesheet.where(person_id: person_ids).where(on_duty: ..span_ends)
                    .select(:id, :person_id, :position_id, :slot_id, :on_duty, :off_duty)
    closed = base.where(on_duty: (span_begins - MAX_SHIFT_LOOKBACK)..)
                 .where(off_duty: span_begins..)
    open = base.where(on_duty: span_begins..).where(off_duty: nil)

    closed.or(open)
  end

  # Overlap, not containment: someone who signs on ten minutes early and off an
  # hour late rangered the shift. The bounds are strict, so the shift before
  # this one -- signing off at the very moment this one starts -- is not
  # counted as having covered it; that zero-length "overlap" is the standard
  # handover, and reporting it read as twelve hours of attendance the person
  # never gave. An open timesheet has to have STARTED inside the shift to
  # count: read as running to now, a sign-on no one closed would otherwise
  # cover every later shift of the position.
  #
  # (Upstream's NoShowReport.php spelled this out as five OR'd branches with
  # non-strict bounds and no open-timesheet case, which counted the handover
  # as coverage and reported everyone still out on the playa as a miss.)
  def covers?(timesheet, slot)
    return false if timesheet.on_duty >= slot.ends
    return timesheet.on_duty >= slot.begins unless timesheet.off_duty

    timesheet.off_duty > slot.begins
  end

  # One narrow query for the people actually rendered, wired back onto the
  # records. Preloading :person on the relations instead pulled the widest
  # table in the schema -- 78 columns including four LONGTEXTs -- for every
  # sign-up and timesheet of the year, to render two fields.
  def attach_people(records)
    people = Person.where(id: records.map(&:person_id).uniq).select(:id, :callsign).index_by(&:id)

    records.each { |record| record.association(:person).target = people[record.person_id] }
  end

  def pair(record) = [record.slot_id, record.person_id]

  # The same placeholder LinkHelper#person_display_name renders, so the sort
  # key and the callsign on the page cannot disagree. (The Laravel-shared
  # schema carries no FKs, so a person row really can be missing.)
  def callsign_for(person, person_id) = person&.callsign || "Deleted ##{person_id}"
end
