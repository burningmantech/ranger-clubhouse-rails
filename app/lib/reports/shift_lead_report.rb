# frozen_string_literal: true

# The Shift Lead Report: who is signed up to ranger a shift period, in the shape
# Khaki reads at the top of a shift -- dirt and Green Dots, command staff,
# special teams, and the positions no one has filled.
#
# Upstream Laravel app/Lib/Reports/ShiftLeadReport.php, rendered by Ember
# reports/shift-lead. OnDutyShiftLeadReport is the live twin and shares this
# class's row shape, position and certification loading, tint rules, and sort.
#
# Upstream also returns an `incoming_positions` list that its own page never
# reads. It is not computed here.
class ShiftLeadReport
  # Which roster a person lands on.
  NON_DIRT = :non_dirt
  COMMAND = :command
  DIRT_AND_GREEN_DOT = :dirt_and_green_dot

  # Minutes a slot must run past the window's start before it counts as
  # overlapping it.
  POSITION_OVERLAP_MIN = 45

  # The Green Dot head count wants a longer tail: someone whose GD shift ends an
  # hour into this one is not Green Dot coverage for it.
  GREEN_DOT_OVERLAP_MIN = 90

  # Being signed up for one of these is what makes a shift a Green Dot shift.
  # GD Mentees are deliberately absent -- a mentee shift is training, not
  # coverage.
  GREEN_DOT_SHIFT_POSITIONS = [Position::DIRT_GREEN_DOT, Position::GREEN_DOT_MENTOR].freeze

  DIRT_POSITIONS = [
    Position::DIRT, Position::DIRT_PRE_EVENT, Position::DIRT_POST_EVENT, Position::DIRT_SHINY_PENNY
  ].freeze

  DIRT_AND_GREEN_DOT_POSITIONS = [
    *DIRT_POSITIONS,
    Position::DIRT_GREEN_DOT, Position::GREEN_DOT_MENTOR, Position::GREEN_DOT_MENTEE
  ].freeze

  # One person on one roster.
  #
  # `begins`/`ends` describe the shift they signed up for; `on_duty`/`duration`
  # describe the entry they are working. A row carries one pair or the other,
  # never both, which is what tells the roster partial which columns to render.
  #
  # `green_dot` and `troubleshooter` are the two chips beside the callsign: a
  # qualified Green Dot, and a Troubleshooter who is neither RSL nor OOD. They
  # are independent -- upstream tints one cell and so can only ever show the
  # first of the two, but a Ranger can be both and the roster says so.
  # `position_title` is what the roster column prints -- the short form. The
  # full title rides alongside it for the places an abbreviation cannot stand on
  # its own: the position filter's options, and the chip naming the choice.
  Ranger = Data.define(:person, :position_title, :position_full_title, :gender, :years, :on_site,
                       :vehicle_blacklisted, :signed_motorpool_agreement, :org_vehicle_insurance,
                       :positions, :certifications, :green_dot, :troubleshooter,
                       :begins, :ends, :begins_day_before, :ends_day_after,
                       :on_duty, :duration) do
    def initialize(begins: nil, ends: nil, begins_day_before: false, ends_day_after: false,
                   on_duty: nil, duration: nil, **)
      super
    end

    def callsign = person.callsign

    # Blacklisted overrides both vehicle columns: the answer to "can they take a
    # rig out" is no, whatever they have signed.
    def gtr
      return :blacklisted if vehicle_blacklisted

      signed_motorpool_agreement ? :yes : :no
    end

    def vehicle
      return :blacklisted if vehicle_blacklisted

      org_vehicle_insurance ? :yes : :no
    end
  end

  # A position running in the window with fewer people than it asks for.
  # `count` is the sign-up count on the scheduled report and the on-duty head
  # count on the live one.
  BelowMin = Data.define(:title, :begins, :ends, :min, :max, :count) do
    # Upstream shows a single number when the range has no width. A zero max
    # means unset rather than "room for no one" -- the column defaults to 0 and
    # hundreds of older slots never had one set -- so it reads as a single
    # number too, instead of the backwards range "1 - 0".
    def need = (max.zero? || min == max) ? min.to_s : "#{min} - #{max}"
  end

  Result = Data.define(:dirt, :command, :special, :below_min,
                       :green_dot_total, :green_dot_females, :shift_start, :on_duty_mode) do
    def on_duty? = on_duty_mode
    def fully_staffed? = below_min.empty?
  end

  # How a roster is ordered, from upstream's shiftLeadComparator.
  SortKey = Data.define(:penny, :title, :begins, :years, :callsign)

  class << self
    # The scheduled report for the window a picked shift opens.
    #
    # shift_duration rather than the slot's own `ends`, because that is what
    # upstream measures the window by and the two can disagree on a slot whose
    # duration column was written by hand.
    def execute(shift_start:, shift_duration:)
      shift_end = shift_start + shift_duration
      year = shift_start.year
      total, females = count_green_dots(shift_start, shift_end)

      Result.new(
        dirt: rangers_for(shift_start, shift_end, DIRT_AND_GREEN_DOT, year),
        command: rangers_for(shift_start, shift_end, COMMAND, year),
        special: rangers_for(shift_start, shift_end, NON_DIRT, year),
        below_min: below_min_for(shift_start, shift_end),
        green_dot_total: total,
        green_dot_females: females,
        shift_start:,
        on_duty_mode: false
      )
    end

    # Constrain a slot query to the slots overlapping the report window.
    #
    # Three ways to overlap, from upstream's buildShiftRange: the slot spans the
    # whole window; or it begins in the hour leading up to the start (and not
    # inside the window's own last hour); or it ends inside the window, at least
    # min_after_start minutes past the start.
    #
    # The `leading` branch carries an end bound upstream does not. Without it
    # that branch constrains only `begins`, so a slot running 11:15-11:45 -- over
    # and done a quarter of an hour before a 12:00 window opens -- still matches,
    # and its sign-ups appear on the roster reading "Shift Ends 11:45". The bound
    # is the same one `trailing` uses, so the two branches now agree on what
    # "still running when we need them" means.
    #
    # begins_year is not part of upstream's rule and does not change which slots
    # match: every branch is bounded within a day of the window. It is here for
    # the query plan -- `ends` carries no index, so without it MariaDB declines
    # the `begins` index and walks every year in the table.
    def overlapping(scope, shift_start, shift_end, min_after_start)
      scope = scope.where(begins_year: [(shift_start - 1.day).year, shift_end.year].uniq)
      cutoff = shift_start + min_after_start.minutes

      spans = scope.where(begins: ..shift_start).where(ends: shift_end..)
      leading = scope.where(begins: (shift_start - 1.hour)...(shift_end - 1.hour)).where(ends: cutoff..)
      trailing = scope.where(ends: cutoff..shift_end)

      spans.or(leading).or(trailing)
    end

    # The SL-relevant positions each person holds, keyed by person id, as
    # [position_id, label] pairs.
    #
    # Plain dirt is excluded because every one of these people is on a dirt
    # shift already -- the column exists to say what ELSE they could be asked to
    # do. The active filter applies only to the current year: a past shift's
    # roster still describes the positions people held at the time.
    def held_positions(person_ids, current_year)
      return {} if person_ids.empty?

      scope = PersonPosition.joins(:position)
                            .where(person_id: person_ids)
                            .where(position: { on_sl_report: true })
                            .where.not(position_id: DIRT_POSITIONS)
      scope = scope.where(position: { active: true }) if current_year

      scope.pluck(:person_id, "position.id", "position.short_title", "position.title")
           .group_by(&:first)
           .transform_values { |rows| rows.map { |row| [row[1], row[2].presence || row[3]] } }
    end

    # The SL-relevant certifications each person holds, keyed by person id, as
    # the titles the report prints. sl_title is the short form written for this
    # report; a certification flagged on to it without one falls back to its
    # full title.
    def held_certifications(person_ids)
      return {} if person_ids.empty?

      titles = Certification.on_sl_report.pluck(:id, :sl_title, :title)
                            .to_h { |id, sl_title, title| [id, sl_title.presence || title] }
      return {} if titles.empty?

      PersonCertification.where(person_id: person_ids, certification_id: titles.keys)
                         .pluck(:person_id, :certification_id)
                         .group_by(&:first)
                         .transform_values { |rows|
                           rows.map { |row| titles[row.last] }.sort_by(&:downcase)
                         }
    end

    # The motorpool agreement and insurance flags for a year, keyed by person id.
    # A person with no person_event row for the year has signed nothing.
    def event_flags(person_ids, year)
      return {} if person_ids.empty?

      PersonEvent.where(person_id: person_ids, year:)
                 .pluck(:person_id, :signed_motorpool_agreement, :org_vehicle_insurance)
                 .to_h { |person_id, motorpool, insurance| [person_id, [motorpool, insurance]] }
    end

    def passed_green_dot_training(person_ids, year)
      Training.did_ids_pass_for_year(person_ids, Position::GREEN_DOT_TRAINING, year)
    end

    # The positions column and the two chips beside the callsign, which decide
    # each other.
    #
    # Holding a GD position only counts as being a Green Dot when the person
    # passed GD training that year and is not standing a mentee shift. When it
    # does not count, the GD entries come out of the list as well -- a shift
    # lead reading "GD" next to a name is reading a promise the person cannot
    # keep. Returns [labels, green_dot, troubleshooter].
    def resolve_positions(held, slot_position_id, passed_training)
      return [[], false, false] if held.blank?

      position_ids = held.map(&:first)
      commands = position_ids.include?(Position::RSC_SHIFT_LEAD) || position_ids.include?(Position::OOD)
      # A Troubleshooter who is also running the shift needs no chip -- the
      # shift lead knows where they are.
      troubleshooter = position_ids.include?(Position::TROUBLESHOOTER) && !commands

      return [held.map(&:last), false, troubleshooter] unless position_ids.intersect?(GREEN_DOT_SHIFT_POSITIONS)

      if passed_training && slot_position_id != Position::GREEN_DOT_MENTEE
        return [held.map(&:last), true, troubleshooter]
      end

      remaining = held.reject { |position_id, _| GREEN_DOT_SHIFT_POSITIONS.include?(position_id) }
      [remaining.map(&:last), false, troubleshooter]
    end

    # Position title as the roster prints it: the short form when there is one,
    # since the column is narrow and the page's legend explains the
    # abbreviations.
    def position_title(position) = position.short_title.presence || position.title

    # Order a roster: Shiny Pennies after everyone, then position title
    # DESCENDING so the Green Dot lines sit above plain dirt, then shift start,
    # then years rangered descending, then callsign.
    #
    # Upstream currently sorts Shiny Pennies to the TOP of the roster. A refactor
    # swapped its '1111' sentinel title for '￿', which collates after every
    # real title and so comes FIRST under a descending sort -- contradicting the
    # comment directly above it, which says twice that pennies belong at the very
    # end. The stated intent is what is ported.
    #
    # Callsign is the last key rather than an unstated tiebreak: upstream leans
    # on a stable JS sort over a callsign-ordered query, and Ruby's sort is not
    # stable.
    def sort_rangers(rows)
      rows.map { |row| [yield(row), row] }
          .sort { |a, b| compare_keys(a.first, b.first) }
          .map(&:last)
    end

    def compare_keys(a, b)
      (a.penny <=> b.penny).nonzero? ||
        (b.title <=> a.title).nonzero? ||
        (a.begins <=> b.begins).nonzero? ||
        (b.years <=> a.years).nonzero? ||
        (a.callsign <=> b.callsign)
    end

    # Narrow a slot or timesheet scope to one roster. Both tables carry
    # position_id and both scopes join :position, so one filter serves the two
    # reports -- which is what keeps them agreeing on what "special teams" means.
    def apply_roster_filter(scope, type)
      case type
      when NON_DIRT
        scope.where.not(position_id: DIRT_AND_GREEN_DOT_POSITIONS)
             .where(position: { type: Position::TYPE_FRONTLINE })
      when COMMAND
        scope.where(position: { type: Position::TYPE_COMMAND })
      when DIRT_AND_GREEN_DOT
        scope.where(position_id: DIRT_AND_GREEN_DOT_POSITIONS)
      else
        raise ArgumentError, "unknown roster type: #{type.inspect}"
      end
    end

    # The Green Dot head count, from whatever pairs of gender columns the caller
    # found: [total, however many of them are women].
    def gender_tally(pairs)
      females = pairs.count { |identity, custom|
        SummarizeGender.parse(identity, custom) == SummarizeGender::FEMALE
      }

      [pairs.size, females]
    end

    # Everything a Ranger row carries that does not depend on where the row came
    # from. The two reports differ only in their last two columns and in where
    # the position and the years come from; this is the rest, so a new column or
    # a changed chip rule lands once.
    def common_ranger_attributes(person:, position:, position_id:, held:, certifications:,
                                 flags:, passed:)
      motorpool, insurance = flags[person.id] || [false, false]
      labels, green_dot, troubleshooter = resolve_positions(held[person.id], position_id,
                                                            passed.key?(person.id))

      {
        person:,
        position_title: position_title(position),
        position_full_title: position.title,
        gender: SummarizeGender.parse(person.gender_identity, person.gender_custom),
        vehicle_blacklisted: person.vehicle_blacklisted,
        signed_motorpool_agreement: motorpool,
        org_vehicle_insurance: insurance,
        positions: labels,
        certifications: certifications[person.id] || [],
        green_dot:,
        troubleshooter:
      }
    end

    private

    # The people signed up for one roster's worth of slots in the window.
    def rangers_for(shift_start, shift_end, type, year)
      current_year = (year == Current.year)
      slot_ids = roster_slot_ids(shift_start, shift_end, type, current_year)
      return [] if slot_ids.empty?

      # person_slot carries no foreign keys -- the Laravel side writes it too --
      # so a row whose person or position has since been deleted reads nil
      # rather than raising, and would take the page down on the first cell.
      rows = PersonSlot.where(slot_id: slot_ids)
                       .includes(:person, slot: :position)
                       .reject { |row| row.person.nil? || row.slot&.position.nil? }
      return [] if rows.empty?

      build_rangers(rows, shift_start, year, current_year)
    end

    def build_rangers(rows, shift_start, year, current_year)
      person_ids = rows.map(&:person_id).uniq
      held = held_positions(person_ids, current_year)
      certifications = held_certifications(person_ids)
      flags = event_flags(person_ids, year)
      passed = passed_green_dot_training(person_ids, year)

      sorted = sort_rangers(rows) { |row| scheduled_sort_key(row) }
      sorted.map { |row| build_ranger(row, shift_start, held, certifications, flags, passed) }
    end

    def build_ranger(row, shift_start, held, certifications, flags, passed)
      person = row.person
      slot = row.slot
      shared = common_ranger_attributes(person:, position: slot.position,
                                        position_id: slot.position_id,
                                        held:, certifications:, flags:, passed:)

      Ranger.new(
        **shared,
        years: person.years_as_ranger.size,
        on_site: person.on_site,
        begins: slot.begins,
        ends: slot.ends,
        # The roster prints clock times only, so a slot reaching past the day the
        # window opens on is marked. Direction, not mere inequality: upstream
        # compares with isSameDay, which marks a slot beginning the day AFTER the
        # window as having begun the day before -- reachable on every evening
        # window, since the leading branch admits starts past midnight.
        begins_day_before: slot.begins.to_date < shift_start.to_date,
        ends_day_after: slot.ends.to_date > shift_start.to_date
      )
    end

    def scheduled_sort_key(row)
      SortKey.new(penny: row.slot.position_id == Position::DIRT_SHINY_PENNY ? 1 : 0,
                  title: row.slot.position.title.to_s.downcase,
                  begins: row.slot.begins,
                  years: row.person.years_as_ranger.size,
                  callsign: row.person.callsign.to_s.downcase)
    end

    # The slots one roster draws from. Past years may reference positions that
    # have since been retired, so the active filter is current-year only.
    def roster_slot_ids(shift_start, shift_end, type, current_year)
      scope = Slot.joins(:position)
      scope = scope.where(position: { active: true }) if current_year
      scope = overlapping(scope, shift_start, shift_end, POSITION_OVERLAP_MIN)

      apply_roster_filter(scope, type).pluck(:id)
    end

    # Positions running in the window with fewer sign-ups than they ask for.
    def below_min_for(shift_start, shift_end)
      scope = Slot.joins(:position)
                  .where(position: { active: true })
                  .where(position: { type: [Position::TYPE_FRONTLINE, Position::TYPE_COMMAND] })
                  .where("slot.signed_up < slot.min")

      # Plucked, not eager-loaded: a hash condition on `position` promotes
      # includes to a join aliasing all 62 columns of both tables and building
      # two AR objects per row, to fill a struct of six fields.
      overlapping(scope, shift_start, shift_end, POSITION_OVERLAP_MIN)
        .pluck("position.title", "slot.begins", "slot.ends", "slot.min", "slot.max", "slot.signed_up")
        .map { |title, begins, ends, min, max, signed_up|
          BelowMin.new(title:, begins:, ends:, min:, max:, count: signed_up)
        }
        .sort_by { |row| row.title.downcase }
    end

    # Green Dots signed up across the window, and how many of them are women.
    #
    # Not deduplicated by person and not filtered on position.active, matching
    # upstream: someone signed up for two GD slots in one window counts twice.
    def count_green_dots(shift_start, shift_end)
      scope = Slot.where(position_id: GREEN_DOT_SHIFT_POSITIONS)
      slot_ids = overlapping(scope, shift_start, shift_end, GREEN_DOT_OVERLAP_MIN).pluck(:id)
      return [0, 0] if slot_ids.empty?

      gender_tally(PersonSlot.where(slot_id: slot_ids)
                             .joins(:person)
                             .pluck("person.gender_identity", "person.gender_custom"))
    end
  end
end
