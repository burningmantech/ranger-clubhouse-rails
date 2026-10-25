# frozen_string_literal: true

# Who signed up for a shift and was never on duty for that position while it
# ran -- a whole year, position by position.
#
# One rule, and it is attendance alone: a sign-up is answered by a timesheet in
# the shift's OWN position that overlaps the shift. Whether that timesheet was
# ever attached to the shift does not enter into it, which is the whole
# difference from the flake report beside it -- that one also excuses a sign-up
# whose timesheet names the slot, even when its hours fall outside the shift.
# So every flake is a no-show, and the handful of no-shows that are not flakes
# are the people whose timesheet claims the shift but whose hours never touched
# it.
#
# (Ported from Laravel app/Lib/Reports/NoShowReport.php. The upstream page had
# the reader tick positions off a team-grouped checkbox grid and reported only
# those; this indexes every position and drills down, as the sibling scheduling
# reports do.)
class NoShowReport
  PositionCount = Data.define(:position_id, :title, :slot_count, :no_show_count,
                              :no_show_slot_count)
  Summary = Data.define(:year, :positions, :slot_count, :no_show_count,
                        :no_show_slot_count)

  NoShow = Data.define(:person, :person_id, :callsign)

  # Only the shifts that produced a no-show get a SlotDetail; the ones everyone
  # honored are counted, not listed.
  SlotDetail = Data.define(:slot, :signup_count, :no_shows)
  PositionDetail = Data.define(:year, :position, :slot_details, :slot_count,
                               :no_show_count) do
    def clean_slot_count = slot_count - slot_details.size
  end

  class << self
    # scanned_slots, without_honored_shifts, attach_people, pair and
    # callsign_for: the attendance rule shared with the flake report.
    include ShiftAttendance

    # Per-position counts for the whole year. Two queries: the sign-up pairs
    # and the shifts are the entire input, and the rule runs over them in Ruby.
    def summary(year:)
      # Four columns, not a pluck: deciding whether a sign-up was honored needs
      # the shift's own hours and position.
      slots = scanned_slots(year).select(:id, :position_id, :begins, :ends).to_a
      slots_by_id = slots.index_by(&:id)
      signups = PersonSlot.where(slot_id: slots.map(&:id)).pluck(:slot_id, :person_id).to_set
      no_shows = without_honored_shifts(signups, slots_by_id)
      by_slot = no_shows.group_by(&:first)

      counts = Hash.new { |hash, position_id| hash[position_id] = Hash.new(0) }
      slots.each { |slot| counts[slot.position_id][:slot] += 1 }
      by_slot.each do |slot_id, rows|
        position_id = slots_by_id[slot_id].position_id
        counts[position_id][:no_show] += rows.size
        counts[position_id][:no_show_slot] += 1
      end

      Summary.new(year:, positions: position_counts(counts), slot_count: slots.size,
                  no_show_count: no_shows.size, no_show_slot_count: by_slot.size)
    end

    # One position's year, shift by shift.
    def position(year:, position:)
      slots = scanned_slots(year).for_position(position.id).ordered_by_begins.to_a
      slots_by_id = slots.index_by(&:id)
      signups = PersonSlot.where(slot_id: slots.map(&:id)).to_a
      # to_set: without_honored_shifts hands back an Array, and this membership
      # test runs once per sign-up of the year.
      kept = without_honored_shifts(signups.map { |signup| pair(signup) }.to_set, slots_by_id).to_set
      no_shows = signups.select { |signup| kept.include?(pair(signup)) }
      attach_people(no_shows)

      PositionDetail.new(year:, position:, slot_count: slots.size,
                         slot_details: slot_details(slots, signups, no_shows.group_by(&:slot_id)),
                         no_show_count: no_shows.size)
    end

    private

    def position_counts(counts)
      titles = Position.titles_by_id(counts.keys)

      counts.map { |position_id, count|
        PositionCount.new(position_id:, title: titles[position_id], slot_count: count[:slot],
                          no_show_count: count[:no_show],
                          no_show_slot_count: count[:no_show_slot])
      }.sort_by { |position| position.title.downcase }
    end

    def slot_details(slots, signups, no_shows_by_slot)
      signup_counts = signups.group_by(&:slot_id).transform_values(&:size)

      slots.filter_map { |slot|
        rows = no_shows_by_slot[slot.id]
        next if rows.blank?

        SlotDetail.new(slot:, signup_count: signup_counts[slot.id].to_i,
                       no_shows: no_show_rows(rows))
      }
    end

    def no_show_rows(signups)
      signups.map { |signup|
        NoShow.new(person: signup.person, person_id: signup.person_id,
                   callsign: callsign_for(signup.person, signup.person_id))
      }.sort_by { |row| row.callsign.downcase }
    end
  end
end
