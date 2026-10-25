# frozen_string_literal: true

# The Shift Lead Report for whoever is on duty right now.
#
# Upstream Laravel app/Lib/Reports/OnDutyShiftLeadReport.php. The live twin of
# ShiftLeadReport, whose row shape, roster filter, position and certification
# loading, chip rules and sort it reuses -- the two reports differ only in where
# the people come from (open timesheets rather than sign-ups), in how they count
# years rangered, and in the roster's last two columns.
class OnDutyShiftLeadReport
  # How far back a sign-in may reach and still count as somebody who is out
  # there now.
  #
  # Upstream bounds an open entry by calendar year alone, which is the pattern
  # OnDutyReport rejects by name for two reasons that both bite here. A shift
  # opened in June and never closed would otherwise stand on the August board
  # reading a duration in the thousands of hours, inflate the Green Dot counts,
  # and -- because the same open entries feed the head count -- silently satisfy
  # a position that is genuinely short. And a year boundary cuts at midnight, so
  # a shift opened at 23:45 on New Year's Eve vanishes at midnight. Longer than
  # any event, short enough that a stale entry from a past one stays off.
  MAX_SHIFT_LOOKBACK = 14.days

  class << self
    def execute(now: nil)
      now ||= Current.time
      year = now.year
      total, females = count_green_dots(now)

      ShiftLeadReport::Result.new(
        dirt: rangers_for(ShiftLeadReport::DIRT_AND_GREEN_DOT, now, year),
        command: rangers_for(ShiftLeadReport::COMMAND, now, year),
        special: rangers_for(ShiftLeadReport::NON_DIRT, now, year),
        below_min: below_min_for(now),
        green_dot_total: total,
        green_dot_females: females,
        shift_start: now,
        on_duty_mode: true
      )
    end

    private

    def rangers_for(type, now, year)
      # timesheet carries no foreign keys, so a row whose person or position has
      # since been deleted reads nil rather than raising.
      rows = ShiftLeadReport.apply_roster_filter(on_duty_scope(now), type)
                            .includes(:person, :position)
                            .reject { |row| row.person.nil? || row.position.nil? }
      return [] if rows.empty?

      person_ids = rows.map(&:person_id).uniq
      # false, not true: upstream's on-duty loader has no active filter at all,
      # and dropping a deactivated position here does not merely shorten the
      # column -- the same list decides the GD and TS chips.
      held = ShiftLeadReport.held_positions(person_ids, false)
      certifications = ShiftLeadReport.held_certifications(person_ids)
      flags = ShiftLeadReport.event_flags(person_ids, year)
      passed = ShiftLeadReport.passed_green_dot_training(person_ids, year)
      years = years_rangered(person_ids)

      sorted = ShiftLeadReport.sort_rangers(rows) { |row| sort_key(row, years) }
      sorted.map { |row| build_ranger(row, held, certifications, flags, passed, years) }
    end

    # Every entry still open that was opened recently enough to be real.
    def on_duty_scope(now)
      Timesheet.joins(:position).on_duty_now.where(on_duty: (now - MAX_SHIFT_LOOKBACK)..now)
    end

    def build_ranger(row, held, certifications, flags, passed, years)
      person = row.person
      shared = ShiftLeadReport.common_ranger_attributes(person:, position: row.position,
                                                        position_id: row.position_id,
                                                        held:, certifications:, flags:, passed:)

      ShiftLeadReport::Ranger.new(
        **shared,
        years: years[person.id].to_i,
        # Signing in happens at an HQ window, so anyone on duty is on site
        # whatever the flag on their record says.
        on_site: true,
        on_duty: row.on_duty,
        # Every row here is still open, so Timesheet#duration measures from the
        # sign-in to now -- which is exactly the elapsed time this column wants.
        duration: row.duration
      )
    end

    # An on-duty row has no slot, so the sort has no shift start to order by --
    # it falls through to years rangered and callsign.
    def sort_key(row, years)
      ShiftLeadReport::SortKey.new(
        penny: row.position_id == Position::DIRT_SHINY_PENNY ? 1 : 0,
        title: row.position.title.to_s.downcase,
        begins: nil,
        years: years[row.person_id].to_i,
        callsign: row.person.callsign.to_s.downcase
      )
    end

    # Years rangered, counted the way upstream counts them HERE: distinct years
    # holding any non-echelon entry.
    #
    # Deliberately not person.years_as_ranger, which the scheduled report uses.
    # That column is materialised under a stricter rule -- Training and Alpha
    # entries excluded, and since 2025 a six-hour floor per year -- so the two
    # reports can print different numbers for the same Ranger. Upstream has the
    # same split; unifying it would change what one of the two pages shows.
    def years_rangered(person_ids)
      Timesheet.where(person_id: person_ids, is_echelon: false)
               .group(:person_id)
               .pluck(:person_id, Arel.sql("COUNT(DISTINCT YEAR(on_duty))"))
               .to_h
    end

    # Positions running right now with fewer people on duty than they ask for.
    #
    # The head count is per POSITION, not per slot: it counts every open entry in
    # the position, whichever slot those people signed into. Upstream does the
    # same, and it is the more useful number -- a shift lead wants to know how
    # many Green Dots are out, not how many are out on one particular slot.
    #
    # Which is why the rows are per position too. Upstream emits one per running
    # slot while counting per position, so a position with two overlapping slots
    # prints the same shortfall twice and counts it twice in every total built
    # from the list. One row per position, taking the widest window across that
    # position's running slots and the smallest minimum it has to meet.
    def below_min_for(now)
      rows = Slot.joins(:position)
                 .where(position: { type: [Position::TYPE_FRONTLINE, Position::TYPE_COMMAND] })
                 .where(begins: ..now).where("slot.ends > ?", now)
                 .pluck("slot.position_id", "position.title", "slot.begins", "slot.ends",
                        "slot.min", "slot.max")
      return [] if rows.empty?

      counts = on_duty_counts(rows.map(&:first).uniq, now)

      rows.group_by(&:first).filter_map { |position_id, group|
        count = counts[position_id].to_i
        min = group.map { |row| row[4] }.min
        next if count >= min

        ShiftLeadReport::BelowMin.new(title: group.first[1],
                                      begins: group.map { |row| row[2] }.min,
                                      ends: group.map { |row| row[3] }.max,
                                      min:, max: group.map { |row| row[5] }.max, count:)
      }.sort_by { |row| row.title.downcase }
    end

    def on_duty_counts(position_ids, now)
      on_duty_scope(now).where(position_id: position_ids).group(:position_id).count
    end

    # Green Dots on duty, and how many of them are women. Counted off open
    # entries rather than sign-ups, so it answers "who is out there now".
    def count_green_dots(now)
      ShiftLeadReport.gender_tally(
        on_duty_scope(now).where(position_id: ShiftLeadReport::GREEN_DOT_SHIFT_POSITIONS)
                          .joins(:person)
                          .pluck("person.gender_identity", "person.gender_custom")
      )
    end
  end
end
