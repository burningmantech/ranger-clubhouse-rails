# frozen_string_literal: true

# Timesheet entries of one event year that look wrong (Ember
# reports/timesheet-sanity-checker port).
#
# Eight named checks. Seven of them are decided from the year's on_duty /
# off_duty / slot-duration columns alone, so they share a single scan: the year
# is plucked once into Row structs and every predicate is a Ruby filter over
# that array. Upstream ran seven separate queries, three of them with raw
# TIMESTAMPDIFF arithmetic in the WHERE clause.
#
# The eighth -- no_credits -- has to price every entry against the year's
# credit table, and is deliberately NOT part of the summary. See #no_credits.
class TimesheetSanityCheckReport
  # What one timesheet row needs to answer all seven cheap checks. Plucked
  # rather than instantiated: 5,600 Timesheet objects to ask "is off_duty nil"
  # is a lot of object for the question.
  Row = Struct.new(:id, :person_id, :position_id, :on_duty, :off_duty,
                   :slot_duration, :suppress, keyword_init: true) do
    # Seconds. An open entry is measured to now, as Timesheet#duration is.
    def duration = ((off_duty || Current.time) - on_duty).to_i

    def open? = off_duty.nil?
  end

  # One overlapping or duplicate finding: a person and the entries that made
  # them a finding. The two person-grain checks both answer in this shape.
  PersonFinding = Struct.new(:person, :person_id, :entries, :pairs, keyword_init: true)

  # How long a shift may run before it is worth a look, for a position that
  # Position::PROBLEM_HOURS does not name. The flag fires past 1.5x this, so
  # 36 hours.
  #
  # Upstream had no such default: it fell back to the SMALLEST value in
  # PROBLEM_HOURS (15, from Gerlach Patrol), which it had computed as a SQL
  # prefilter and then reused as a threshold. Every unlisted position was
  # therefore flagged past 22.5 hours by accident. A day is the deliberate
  # ceiling that replaces it.
  DEFAULT_MAX_HOURS = 24

  # Past this multiple of the recommended maximum -- or of the scheduled
  # shift's own length -- an entry is flagged. Upstream's number, kept.
  TOO_LONG_MULTIPLIER = 1.5

  # key: what the URL and the metadata tables are keyed by.
  # band: who acts on it, which is how the index groups them.
  # grain: what the count counts. The two person-grain checks must never be
  #        added to the entry-grain ones -- see #summary.
  CHECKS = [
    { key: :on_duty, band: :contact, grain: :entries },
    { key: :end_before_start, band: :contact, grain: :entries },
    { key: :overlapping, band: :contact, grain: :people },
    { key: :too_long_for_shift, band: :review, grain: :entries },
    { key: :too_short, band: :review, grain: :entries },
    { key: :too_long, band: :review, grain: :entries },
    { key: :duplicate_alphas, band: :review, grain: :people },
    { key: :no_credits, band: :configuration, grain: :entries }
  ].freeze

  KEYS = CHECKS.map { _1[:key] }.freeze

  # The one check the summary cannot afford, kept in a constant so the index
  # view and the summary agree about which row has no number.
  DEFERRED_KEY = :no_credits

  BANDS = CHECKS.map { _1[:band] }.uniq.freeze

  # counts: {key => Integer} for every check but the deferred one.
  # rangers_to_contact / entries_to_review: de-duplicated across the checks of
  # a band, because the same entry trips several predicates routinely (a
  # two-minute entry that also ends before it starts is one entry, not two).
  Summary = Struct.new(:counts, :rangers_to_contact, :entries_to_review,
                       keyword_init: true) do
    def clear_count = counts.values.count(&:zero?)

    # Every check on the board, not just the counted ones. Reading `counts.size`
    # here made a clean year say "7 of 7 checks clear" above eight rows, one of
    # which had not been run at all -- the most consequential one.
    def checked_count = KEYS.size
  end

  class << self
    def summary(year:)
      rows = scan(year)
      found = KEYS.index_with { |key| key == DEFERRED_KEY ? [] : send(key, rows) }

      Summary.new(
        counts: found.except(DEFERRED_KEY).transform_values(&:size),
        rangers_to_contact: person_ids(found, :contact).size,
        entries_to_review: entry_ids(found, :review).size
      )
    end

    # The rows of one check, loaded and ordered for display. Person-grain
    # checks answer PersonFindings; the rest answer Timesheets.
    #
    # limit: caps what comes back, for the page that has to render it. Only
    # no_credits needs it -- see there -- and the export passes nothing, since
    # a spreadsheet is exactly how you handle two thousand rows.
    def findings(year:, check:, limit: nil)
      return no_credits(year, limit:) if check == DEFERRED_KEY

      found = send(check, scan(year))
      case check
      when :overlapping then load_overlapping(found)
      when :duplicate_alphas then load_duplicate_alphas(found)
      else load_entries(found, order: entry_order(check))
      end
    end

    def band(key) = CHECKS.find { _1[:key] == key }&.fetch(:band)

    def grain(key) = CHECKS.find { _1[:key] == key }&.fetch(:grain)

    def keys_in_band(name) = CHECKS.select { _1[:band] == name }.map { _1[:key] }

    private

    # The year in one query. left_joins because most entries have no slot, and
    # an inner join would quietly drop them from six checks that do not care
    # about slots at all.
    def scan(year)
      Timesheet.for_year(year)
               .left_joins(:slot)
               .pluck(:id, :person_id, :position_id, :on_duty, :off_duty,
                      "slot.duration", :suppress_duration_warning)
               .map { Row.new(id: _1[0], person_id: _1[1], position_id: _1[2],
                              on_duty: _1[3], off_duty: _1[4],
                              slot_duration: _1[5], suppress: _1[6]) }
    end

    # --- the seven cheap checks -------------------------------------------
    # Each answers an Array of Rows, or of PersonFindings for the two
    # person-grain ones. Ordering for display happens after loading.

    def on_duty(rows) = rows.select(&:open?)

    # Impossible rather than merely odd: the entry signs out before it signs
    # in. Open entries cannot qualify and are excluded rather than compared
    # against Current.time, which would flag every one of them.
    def end_before_start(rows)
      rows.reject(&:open?).select { _1.on_duty > _1.off_duty }
    end

    # Two closed entries of the same person running at once. Compared against
    # off_duty directly; upstream compared against on_duty + duration, which is
    # the same number by construction and says nothing about what is tested.
    #
    # Every earlier entry is compared, not just the immediately previous one.
    # Upstream walked consecutive pairs only, so an entry swallowing three
    # later ones reported ONE pair and the short entries inside it were
    # measured against each other instead -- the reader fixed the single pair
    # shown and the rest never surfaced on any later run.
    def overlapping(rows)
      rows.reject(&:open?)
          .group_by(&:person_id)
          .filter_map do |person_id, entries|
            sorted = entries.sort_by(&:on_duty)
            pairs = overlapping_pairs(sorted)
            next if pairs.empty?

            # entries as well as pairs: the band arithmetic counts entries, and
            # an entry overlapping both its neighbours appears in two pairs.
            PersonFinding.new(person_id:, pairs:, entries: pairs.flatten.uniq)
          end
    end

    # Every entry paired with each earlier one it still runs inside. Quadratic
    # in one person's entries for the year, which is a few dozen at most.
    def overlapping_pairs(sorted)
      sorted.each_with_index.flat_map do |entry, index|
        sorted[0...index].filter_map { |prev| [prev, entry] if entry.on_duty < prev.off_duty }
      end
    end

    # Longer than the position is meant to run.
    #
    # Closed entries only, as upstream has it. An open entry measures to now,
    # so every unsigned-out entry of a past year is automatically longer than
    # any threshold -- the check would answer with a copy of "Still on duty"
    # for every year but the current one, which is exactly the noise the board
    # is meant to remove.
    #
    # suppress_duration_warning is deliberately NOT honoured here, matching
    # upstream: the flag is offered when a Ranger's own shift ran long against
    # its SCHEDULE, and it does not amount to vouching for a day-and-a-half.
    def too_long(rows)
      rows.reject(&:open?).select do |row|
        max = Position::PROBLEM_HOURS.fetch(row.position_id, DEFAULT_MAX_HOURS)
        row.duration > max * 3600 * TOO_LONG_MULTIPLIER
      end
    end

    # Longer than the shift the entry was signed up for. Zero-length slots are
    # skipped: the column defaults to 0, and any duration at all clears
    # `>= 0`, which would flag every entry attached to one.
    # Closed entries only, for the reason spelled out above: an open entry
    # measures to now, so every unsigned-out entry with a slot would sit here
    # permanently with a duration that grows on each page load, restating what
    # "Still on duty" already says. Upstream's IFNULL(off_duty, now) included
    # them; the same argument that took them out of too_long takes them out
    # here.
    def too_long_for_shift(rows)
      rows.reject(&:open?).select do |row|
        !row.suppress && row.slot_duration.to_i.positive? &&
          row.duration >= row.slot_duration * TOO_LONG_MULTIPLIER
      end
    end

    # Fifteen minutes or less, and closed -- an open entry is a minute old the
    # moment it starts.
    #
    # Measured in seconds against Timesheet::TOO_SHORT_LENGTH. Upstream
    # compared TIMESTAMPDIFF(MINUTE, ...) <= 15, which truncates, so it also
    # caught entries up to 15:59.
    # duration.positive? as well as the ceiling: an entry that signs out before
    # it signs in has a NEGATIVE duration, which clears `<= 900` trivially, and
    # the :shortest ordering then puts a fifteen-hour-backwards entry at the
    # top of a page headed "fifteen minutes or less". Those rows belong to
    # end_before_start, which reports them with both times.
    def too_short(rows)
      rows.reject(&:open?)
          .select do |row|
            !row.suppress && row.duration.positive? &&
              row.duration <= Timesheet::TOO_SHORT_LENGTH
          end
    end

    # A Ranger walks Alpha once. More than one entry means one of them belongs
    # to a different position, or to no one.
    def duplicate_alphas(rows)
      rows.select { _1.position_id == Position::ALPHA }
          .group_by(&:person_id)
          .filter_map do |person_id, entries|
            next if entries.size < 2

            PersonFinding.new(person_id:, entries: entries.sort_by(&:on_duty))
          end
    end

    # --- the deferred check ------------------------------------------------

    # Every entry of the year priced against the year's credit table, keeping
    # the ones worth nothing.
    #
    # Not in the summary, and not cached: this is the only check that has to
    # read the credit cache, and the index would pay for it on every load of
    # every year to put one more number on screen.
    #
    # TimesheetCredits prices a row whose position has been deleted at 0.0, so
    # those entries land here by construction. They belong here -- those hours
    # really do earn nothing -- but the page has to say which kind of nothing
    # it is looking at, since no credit table can be fixed to repair them.
    #
    # limit: because this is the one check with no ceiling of its own. Every
    # other predicate describes something unusual; this one describes "earns
    # nothing", and a year whose position_credit table was never filled in
    # answers with the entire year -- 2,284 rows for 2010, none of which the
    # reader can act on one at a time. The page asks for a page's worth and
    # says so; the CSV still takes the lot.
    def no_credits(year, limit: nil)
      # Priced with only the position preloaded, which is all the arithmetic
      # reads. Preloading person and slot over the whole year to display a
      # fraction of it pulled every Ranger and every shift of the year into
      # memory to be thrown away.
      priced = Timesheet.for_year(year).includes(:position).to_a
      credits = TimesheetCredits.credits_by_id(priced)
      flagged = priced.select { credits[_1.id].to_f.zero? }.map(&:id)

      entries = Timesheet.where(id: flagged)
                         .includes(:person, :position, :slot)
                         .to_a
                         .sort_by { [position_title(_1).downcase, callsign(_1).downcase] }

      limit ? entries.first(limit) : entries
    end

    # --- loading and ordering ----------------------------------------------

    # Ordering is applied after loading because duration is computed, not a
    # column, and callsign lives on another table.
    def load_entries(found, order:)
      entries = Timesheet.where(id: found.map(&:id))
                         .includes(:person, :position, :slot)
                         .to_a
      case order
      when :callsign then entries.sort_by { callsign(_1).downcase }
      when :longest then entries.sort_by { -_1.duration }
      when :shortest then entries.sort_by(&:duration)
      end
    end

    def entry_order(check)
      case check
      when :too_long, :too_long_for_shift then :longest
      when :too_short then :shortest
      else :callsign
      end
    end

    def load_overlapping(found)
      people = people_by_id(found)
      entries = entries_by_id(found.flat_map { _1.pairs.flatten })

      found.map do |finding|
        pairs = finding.pairs.map { |pair| pair.filter_map { entries[_1.id] } }
        # entries: carried through as well as pairs. The export reads it, and a
        # loader that dropped it turned the whole CSV into a header row.
        # compact/filter_map because a row deleted between the scan and this
        # load misses the hash and would otherwise render as nil.
        PersonFinding.new(person: people[finding.person_id], person_id: finding.person_id,
                          pairs:, entries: pairs.flatten.uniq)
      end.sort_by { callsign_of(_1).downcase }
    end

    def load_duplicate_alphas(found)
      people = people_by_id(found)
      entries = entries_by_id(found.flat_map(&:entries))

      found.map do |finding|
        PersonFinding.new(person: people[finding.person_id], person_id: finding.person_id,
                          entries: finding.entries.filter_map { entries[_1.id] })
      end.sort_by { callsign_of(_1).downcase }
    end

    def people_by_id(found)
      Person.where(id: found.map(&:person_id)).index_by(&:id)
    end

    # :person as well, though the person-grain views read finding.person: the
    # CSV export walks these entries directly and asks each one for its person
    # and email, which without the preload is a query per exported row.
    def entries_by_id(rows)
      Timesheet.where(id: rows.map(&:id)).includes(:person, :position, :slot).index_by(&:id)
    end

    # --- band arithmetic ----------------------------------------------------

    def person_ids(found, band_name)
      keys_in_band(band_name).flat_map { |key| found[key].map(&:person_id) }.uniq
    end

    # Entry ids, so an entry caught by three checks counts once. The
    # person-grain checks contribute the entries behind their findings.
    def entry_ids(found, band_name)
      keys_in_band(band_name).flat_map do |key|
        found[key].flat_map do |finding|
          finding.is_a?(PersonFinding) ? Array(finding.entries).map(&:id) : [finding.id]
        end
      end.uniq
    end

    # The schema carries no app-domain foreign keys, so both of these read nil
    # on a row whose person or position has been deleted. Sorted under a
    # printable stand-in rather than crashing the sort.
    #
    # The stand-in is the one the page prints. Spelling "Person #<id>" here
    # while person_display_name renders "Deleted #<id>" filed every deleted
    # person under P and showed them labelled D, so a callsign-ordered table
    # read as unsorted.
    def callsign(entry) = deleted_name(entry.person, entry.person_id)

    def callsign_of(finding) = deleted_name(finding.person, finding.person_id)

    def deleted_name(person, person_id)
      person&.callsign || ApplicationController.helpers.person_display_name(person, person_id)
    end

    def position_title(entry) = entry.position&.title || "Position ##{entry.position_id}"
  end
end
