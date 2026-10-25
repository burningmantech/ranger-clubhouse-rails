# frozen_string_literal: true

# Who signed up for a shift and never rangered it, and who rangered a shift
# they never signed up for -- across a whole year, position by position.
#
# The report turns on one join: `timesheet.slot_id`. A sign-up is answered by
# the timesheet that names the same slot.
#
#   flake  a person_slot row with no timesheet carrying that slot_id for that
#          person -- UNLESS the person holds a timesheet in the shift's own
#          position that overlaps it anyway. They rangered the shift; only the
#          link is missing, and roughly a third of timesheets carry no slot_id
#          at all, so chasing them would be chasing bookkeeping. A timesheet
#          for a DIFFERENT position does not excuse the sign-up: the shift went
#          uncovered either way, and the row names where the person was.
#   rogue  a timesheet carrying the slot_id whose person never signed up.
#
# (Replaces the instant-in-time report ported from Laravel
# app/Lib/Reports/FlakeReport.php, which matched on position plus time window
# to answer "who is flaking right now". /timesheets/on-duty answers that.)
class FlakeReport
  PositionCount = Data.define(:position_id, :title, :slot_count, :flake_count,
                              :rogue_count, :unstaffed_slot_count)
  Summary = Data.define(:year, :positions, :slot_count, :flake_count, :rogue_count,
                        :unstaffed_slot_count)

  # timesheet is a timesheet for ANOTHER position overlapping the shift, nil
  # when the person has none -- a same-position one would have cleared the
  # sign-up entirely, so it can never appear here.
  Flake = Data.define(:person, :person_id, :callsign, :timesheet,
                      :timesheet_position_title)

  # position_title is set only when the timesheet is for a position other than
  # the shift's. outside_shift marks a timesheet linked to this slot whose own
  # hours fall outside it -- the link is the definition, but the row must not
  # read as if the person was here.
  Rogue = Data.define(:person, :person_id, :callsign, :timesheet,
                      :position_title, :outside_shift)

  # Only the shifts that produced a flake or a rogue get a SlotDetail; the
  # clean ones are counted, not listed.
  SlotDetail = Data.define(:slot, :signup_count, :flakes, :rogues)
  PositionDetail = Data.define(:year, :position, :slot_details, :slot_count,
                               :flake_count, :rogue_count, :unstaffed_slot_count) do
    # Shifts with sign-ups that everyone honored. A shift no one signed up for
    # is not clean -- it is uncovered, and counted on its own.
    def clean_slot_count = slot_count - slot_details.size - unstaffed_slot_count
  end

  class << self
    # scanned_slots, without_honored_shifts, covers?, attach_people, pair and
    # callsign_for: the attendance rule this report shares with the no-shows
    # report beside it.
    include ShiftAttendance

    # Per-position counts for the whole year. Three queries, all plucks: the
    # sign-up and timesheet pairs are the entire input, and set arithmetic in
    # Ruby is cheaper and far shorter than the NOT EXISTS joins that would
    # produce the same two numbers.
    def summary(year:)
      # Four columns, not a pluck: deciding whether a sign-up was honored
      # without its slot link needs the shift's own hours and position, and
      # the same covers? the drill-down uses reads them off a Slot.
      slots = scanned_slots(year).select(:id, :position_id, :begins, :ends).to_a
      slots_by_id = slots.index_by(&:id)
      slot_ids = slots.map(&:id)
      signups = signup_pairs(slot_ids)
      # Rows, not pairs: one person can hold two timesheets against one slot
      # (timesheet.slot_id has no unique index, and signing off and back on
      # during a shift produces exactly that). The drill-down lists both, so
      # collapsing them here made the index badge disagree with the page it
      # links to.
      linked_rows = linked_pairs(slot_ids)
      linked = linked_rows.to_set

      flakes = without_honored_shifts(signups - linked, slots_by_id)
      rogues = linked_rows.reject { |pair| signups.include?(pair) }
      # No one signed up and no one was on duty: the shift produces no row at
      # all, so without its own count it reads as a clean shift rather than as
      # the coverage gap it is.
      touched = (signups.map(&:first) + linked_rows.map(&:first)).to_set

      counts = Hash.new { |hash, position_id| hash[position_id] = Hash.new(0) }
      slots.each do |slot|
        counts[slot.position_id][:slot] += 1
        counts[slot.position_id][:unstaffed] += 1 unless touched.include?(slot.id)
      end
      flakes.each { |slot_id, _| counts[slots_by_id[slot_id].position_id][:flake] += 1 }
      rogues.each { |slot_id, _| counts[slots_by_id[slot_id].position_id][:rogue] += 1 }

      Summary.new(year:,
                  positions: position_counts(counts),
                  slot_count: slot_ids.size,
                  flake_count: flakes.size,
                  rogue_count: rogues.size,
                  unstaffed_slot_count: slot_ids.count { |slot_id| !touched.include?(slot_id) })
    end

    # One position's year, shift by shift.
    def position(year:, position:)
      slots = scanned_slots(year).for_position(position.id).ordered_by_begins.to_a
      slots_by_id = slots.index_by(&:id)
      slot_ids = slots.map(&:id)
      signups = PersonSlot.where(slot_id: slot_ids).to_a
      sheets = Timesheet.where(slot_id: slot_ids).to_a
      signed_up = signups.map { |signup| pair(signup) }.to_set
      linked = sheets.map { |sheet| pair(sheet) }.to_set

      unlinked = signups.reject { |signup| linked.include?(pair(signup)) }
      kept = without_honored_shifts(unlinked.map { |signup| pair(signup) }.to_set, slots_by_id)
      flakes = unlinked.select { |signup| kept.include?(pair(signup)) }
      rogues = sheets.reject { |sheet| signed_up.include?(pair(sheet)) }
      attach_people(flakes + rogues)

      details = slot_details(slots, signups, flakes.group_by(&:slot_id),
                             rogues.group_by(&:slot_id),
                             covering_timesheets(flakes.map(&:person_id).uniq, slots))
      touched = (signups.map(&:slot_id) + sheets.map(&:slot_id)).to_set

      PositionDetail.new(year:, position:, slot_details: details, slot_count: slots.size,
                         flake_count: flakes.size, rogue_count: rogues.size,
                         unstaffed_slot_count: slots.count { |slot| !touched.include?(slot.id) })
    end

    private

    def signup_pairs(slot_ids)
      PersonSlot.where(slot_id: slot_ids).pluck(:slot_id, :person_id).to_set
    end

    def linked_pairs(slot_ids)
      Timesheet.where(slot_id: slot_ids).pluck(:slot_id, :person_id)
    end

    def position_counts(counts)
      titles = Position.titles_by_id(counts.keys)

      counts.map { |position_id, count|
        PositionCount.new(position_id:, title: titles[position_id], slot_count: count[:slot],
                          flake_count: count[:flake], rogue_count: count[:rogue],
                          unstaffed_slot_count: count[:unstaffed])
      }.sort_by { |position| position.title.downcase }
    end

    def slot_details(slots, signups, flakes_by_slot, rogues_by_slot, sheets_by_person)
      signup_counts = signups.group_by(&:slot_id).transform_values(&:size)
      titles = position_titles(sheets_by_person.values.flatten + rogues_by_slot.values.flatten)

      slots.filter_map { |slot|
        flakes = flakes_by_slot[slot.id] || []
        rogues = rogues_by_slot[slot.id] || []
        next if flakes.empty? && rogues.empty?

        SlotDetail.new(slot:,
                       signup_count: signup_counts[slot.id].to_i,
                       flakes: flake_rows(flakes, slot, sheets_by_person, titles),
                       rogues: rogue_rows(rogues, slot, titles))
      }
    end

    def flake_rows(flakes, slot, sheets_by_person, titles)
      flakes.map { |signup|
        timesheet = covering_timesheet(sheets_by_person[signup.person_id], slot)

        Flake.new(person: signup.person, person_id: signup.person_id,
                  callsign: callsign_for(signup.person, signup.person_id),
                  timesheet:,
                  timesheet_position_title: (titles[timesheet.position_id] if timesheet))
      }.sort_by { |row| row.callsign.downcase }
    end

    # The position title rides along whenever the timesheet is for another
    # position -- rogues are matched on the slot link alone, so one can be.
    def rogue_rows(rogues, slot, titles)
      rogues.map { |timesheet|
        other_position = timesheet.position_id != slot.position_id

        Rogue.new(person: timesheet.person, person_id: timesheet.person_id,
                  callsign: callsign_for(timesheet.person, timesheet.person_id),
                  timesheet:,
                  position_title: (titles[timesheet.position_id] if other_position),
                  outside_shift: !covers?(timesheet, slot))
      }.sort_by { |row| row.callsign.downcase }
    end

    # Every timesheet a flake holds anywhere in the position's own span, in one
    # query for the whole page; the per-shift match happens in Ruby.
    def covering_timesheets(person_ids, slots)
      return {} if person_ids.empty? || slots.empty?

      timesheet_window(person_ids, slots.map(&:begins).min, slots.map(&:ends).max)
        .order(:on_duty).group_by(&:person_id)
    end

    # Where the person was instead. A same-position timesheet cannot turn up
    # here -- one would have cleared the sign-up before the row was built --
    # so this is always another position's, and the one that spent the most
    # time inside the shift is the answer.
    def covering_timesheet(timesheets, slot)
      candidates = (timesheets || []).select { |timesheet| covers?(timesheet, slot) }

      candidates.max_by { |timesheet| overlap(timesheet, slot) }
    end

    # An open timesheet is still running, so within this shift it reaches the
    # shift's end. Scoring it at its sign-on instant instead made it exactly
    # zero every time, and the person still out there lost the tie-break to
    # any closed sheet with a minute in the window.
    def overlap(timesheet, slot)
      finish = [timesheet.off_duty || slot.ends, slot.ends].min
      start = [timesheet.on_duty, slot.begins].max

      [finish - start, 0].max
    end

    # One query for the whole page. Position.titles_by_id carries the
    # missing-position placeholder.
    def position_titles(timesheets)
      Position.titles_by_id(timesheets.map(&:position_id).uniq)
    end
  end
end
