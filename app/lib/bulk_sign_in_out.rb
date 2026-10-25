# frozen_string_literal: true

# Parse, verify, and commit Bulk Sign In/Out lines — the port of the Laravel
# App\Lib\BulkSignInOut (staged upstream at api/app/Lib/BulkSignInOut.php).
#
# One pasted line per Ranger. The action is inferred from the shape of the
# columns rather than chosen from a menu, which is what makes this page fast to
# use and worth the parser. The eight shapes are LINE_FORMATS below -- listed
# once, because the help panel renders that same constant and a second copy here
# would be free to drift from it.
#
# The ambiguity between "second column is a position" and "second column is a
# time" is resolved by shape alone, in upstream's order: a two-column line whose
# second field parses as a time is a sign out, otherwise a sign in.
#
# Every line is checked against live state (callsign, position held, on/off duty,
# overlaps) and the page refuses to write anything unless every line passes.
module BulkSignInOut
  # HH:MM or HHMM, bounded. \A..\z rather than ^$ -- ^$ match at line boundaries,
  # so "0730\n; rm -rf" would pass a ^$ anchored check.
  TIME_REGEXP = /\A([01]?\d|2[0-3]):?([0-5]\d)\z/

  # MM-DD, MM/DD, either with an optional -YY or -YYYY (or the / spellings).
  #
  # Two digits or four, not upstream's two-to-four: a three-digit year passes
  # PHP's checkdate, so a dropped keystroke in "08/15/2026" built a timesheet in
  # the year 202. Nothing downstream catches it -- the review table prints
  # weekday, month, day and time without a year, so the row reads as correct.
  DATE_REGEXP = %r{\A(\d{1,2})[-/](\d{1,2})(?:[-/](\d{2}|\d{4}))?\z}

  # The 007 position reads as a valid time (00:7 -> 00:07), so the title is
  # excluded by name. Upstream excludes it from the date check as well; a title
  # with no separator cannot match DATE_REGEXP, but the pair is kept together so
  # the two checks stay obviously symmetrical.
  POSITION_007 = "007"

  AUDIT_REASON = "bulk sign in/out"

  # How each inferred action reads in the review table.
  ACTION_LABELS = {
    in: "sign in",
    out: "sign out",
    inout: "sign in & out",
    unknown: "not understood"
  }.freeze

  # The line shapes, in the order parse_columns actually tries them -- within
  # each column count, the shape whose test runs first comes first. Kept beside
  # the parser (as BulkUpload::TicketHandler.line_formats is) so the help a
  # reader follows cannot drift from the rules it describes, and rendered
  # verbatim by the help panel.
  LINE_FORMATS = [
    ["callsign,time", "Signs out at that time today"],
    ["callsign,position", "Signs in for that position, starting now"],
    ["callsign,date,time", "Signs out at that date and time"],
    ["callsign,position,time", "Signs in for that position at that time today"],
    ["callsign,position,time,time",
     "Signs in and out today. A shift ending earlier than it starts ends the next morning."],
    ["callsign,position,date,time", "Signs in for that position at that date and time"],
    ["callsign,position,date,time,time",
     "Signs in and out, ending the same day — or the next morning, if the end time is " \
     "earlier than the start."],
    ["callsign,position,date,time,date,time", "Signs in and out across the two dates you name"]
  ].freeze

  # How many lines one paste may carry. A pasted spreadsheet column is a
  # realistic accident, and every line costs several queries to check and lands
  # in a single transaction -- 100,000 of them would hold locks across three
  # tables for the length of the request.
  MAX_LINES = 1000

  # The years a typed date may name. Two-digit years always expand to 20xx and
  # four-digit ones were taken as given, so "08/15/98" quietly booked a shift in
  # 2098 and "08/15/0000" reached below MariaDB's DATETIME floor and raised
  # mid-commit instead of landing in the review table. Next year is the ceiling
  # because an event runs across a year end; nothing beyond it is a record of
  # something that happened.
  EARLIEST_YEAR = 1996

  # One parsed line. `raw` is kept so a line that never resolved to a person
  # still has something to show in the review table.
  Entry = Struct.new(:raw, :person, :person_id, :callsign, :action, :timesheet_id,
                     :position_id, :position_title, :signin, :signout, :errors,
                     keyword_init: true) do
    # What the admin log records for this line.
    #
    # `person` is dropped deliberately. It is here so the review table can build
    # a link, but a plain to_h hands the whole ActiveRecord object to the JSON
    # coder -- email, street address, emergency contact and all -- and
    # action_log.data would end up holding a copy of every Ranger in the batch.
    # Upstream logs ids and times, which is what an audit trail needs.
    def to_log = to_h.except(:person)
  end

  class << self
    # Parse every line. Returns [entries, have_error].
    def parse(lines)
      positions = Position.select(:id, :title).index_by { |position| position.title.downcase }

      entries = lines.to_s.split("\n").filter_map do |line|
        line = line.strip
        process_line(line, positions) unless line.empty?
      end

      if entries.size > MAX_LINES
        entries = entries.first(MAX_LINES)
        entries.last.errors << "more than #{MAX_LINES} lines were pasted — " \
                               "split the list and do it in batches"
      end

      flag_conflicting_lines(entries)

      [entries, entries.any? { |entry| entry.errors.any? }]
    end

    # Commit the parsed entries. Returns true if any entry failed to save.
    #
    # Entries carrying errors are skipped rather than refused: the controller
    # has already refused the whole batch by then, and skipping keeps this
    # method safe to call with a mixed list.
    def process(entries, user:)
      have_error = false

      ApplicationRecord.transaction do
        entries.each do |entry|
          next if entry.errors.any? || entry.action == :unknown

          have_error = true unless persist_entry(entry, user)
        end

        # Upstream commits whatever succeeded and merely reports the rest. This
        # page promises the operator, in as many words, that it saves every line
        # or none of them -- so a write that fails after its checks passed takes
        # the batch down with it, and the review page that follows can honestly
        # say nothing was saved.
        #
        # Rolls back the rows, the audit logs, and any status conversion. A
        # conversion notice already handed to the mailer is the one thing that
        # cannot be recalled, which is a fair price for not lying about what is
        # in the database.
        raise ActiveRecord::Rollback if have_error
      end

      have_error
    end

    # Does the value look like a time? (HH:MM or HHMM, valid ranges)
    def time?(value)
      value != POSITION_007 && TIME_REGEXP.match?(value)
    end

    # Does the value look like a date? (MM/DD with an optional year)
    def date?(value)
      value != POSITION_007 && DATE_REGEXP.match?(value)
    end

    private

    # Every check in process_line asks the database, which does not yet know
    # about the other lines in the same paste -- so two lines naming one Ranger
    # both see the state from before either of them, and both pass. Pasting
    # "crow,dirt" twice used to create two timesheets with no off duty; closing
    # one leaves the other open forever, which is the row Mass Sign-Out exists to
    # sweep up. Two overlapping sign in & outs likewise both passed the overlap
    # check and double-credited the hours.
    #
    # So the batch is checked against itself, once, after every line is parsed.
    def flag_conflicting_lines(entries)
      entries.reject { |entry| entry.errors.any? || entry.person_id.nil? }
             .group_by(&:person_id)
             .each_value { |rows| flag_person_conflicts(rows) if rows.size > 1 }
    end

    def flag_person_conflicts(rows)
      claimed = []

      rows.each do |row|
        window = shift_window(row)
        next if window.nil?

        if claimed.any? { |other| windows_overlap?(window, other) }
          row.errors << "another line above already signs #{row.callsign} in or out " \
                        "for this time"
        else
          claimed << window
        end
      end
    end

    # The stretch of time a line lays claim to, as [start, end]. A nil end means
    # the shift is left open, which conflicts with everything after it.
    def shift_window(entry)
      case entry.action
      when :in then [entry.signin || Current.time, nil]
      when :out, :inout then [entry.signin, entry.signout]
      end
    end

    # Touching end to end is not a clash -- one shift may start the moment
    # another finishes -- so the comparison is strict.
    def windows_overlap?(first, second)
      first_start, first_end = first
      second_start, second_end = second
      return false if first_start.nil? || second_start.nil?

      (first_end.nil? || first_end > second_start) &&
        (second_end.nil? || second_end > first_start)
    end

    def process_line(line, positions)
      # split(",", -1) keeps trailing empty fields, so "crow,dirt,0845," is the
      # four-column form with an empty time and says so, rather than silently
      # becoming the three-column sign in the reader did not type.
      columns = line.split(",", -1).map(&:strip)

      if columns[0].blank?
        return Entry.new(raw: line, action: :unknown, errors: ["Callsign not specified"])
      end

      callsign = columns[0]
      action, signin, signout, position_name, errors = parse_columns(columns)

      person = Person.retrieve_by_callsign(callsign)
      callsign = person.callsign if person

      timesheet = nil

      if person.nil?
        errors << "callsign '#{callsign}' not found"
      elsif errors.empty?
        timesheet, signin, state_errors = validate_timesheet_state(person.id, action, signin, signout)
        errors.concat(state_errors)
      end

      position_id, position_name, position_errors =
        resolve_position(position_name, positions, person&.id, timesheet, action)
      errors.concat(position_errors)

      # Upstream lets a sign in with no position through to a save failure at
      # commit time, where the message names a database column. Saying it here
      # means the reader sees it in the review table with the rest.
      if position_id.nil? && [:in, :inout].include?(action) && errors.empty?
        errors << "position not specified"
      end

      Entry.new(raw: line, person:, person_id: person&.id, callsign:, action:,
                timesheet_id: timesheet&.id, position_id:, position_title: position_name,
                signin:, signout:, errors:)
    end

    # Split the columns into an action, sign in/out times, and a position name.
    # Returns [action, signin, signout, position_name, errors].
    def parse_columns(columns)
      field = columns[1].to_s
      errors = []
      action = :unknown
      signin = signout = position = nil

      case columns.size
      when 1
        errors << "too few columns - need at least a time or position"

      # callsign,time     - sign out at time
      # callsign,position - sign in now
      when 2
        if time?(field)
          action = :out
          signout = parse_time(field, "sign out", errors)
        else
          action = :in
          position = field
        end

      # callsign,date,time     - sign out at date & time
      # callsign,position,time - sign in at time today
      when 3
        if date?(field)
          action = :out
          signout = parse_date_and_time(field, columns[2], "sign out", errors)
        else
          action = :in
          position = field
          signin = parse_time(columns[2], "sign in", errors)
        end

      # callsign,position,time,time - sign in & out today
      # callsign,position,date,time - sign in at date & time
      when 4
        position = field
        if time?(columns[2])
          action = :inout
          signin = parse_time(columns[2], "sign in", errors)
          signout = same_day_signout(signin, columns[3], errors)
        else
          action = :in
          signin = parse_date_and_time(columns[2], columns[3], "sign in", errors)
        end

      # callsign,position,date,time,time - sign in & out, ending the same day
      when 5
        position = field
        action = :inout
        signin = parse_date_and_time(columns[2], columns[3], "sign in", errors)
        signout = same_day_signout(signin, columns[4], errors)

      # callsign,position,date,time,date,time - sign in & out across days
      when 6
        position = field
        action = :inout
        signin = parse_date_and_time(columns[2], columns[3], "sign in", errors)
        signout = parse_date_and_time(columns[4], columns[5], "sign out", errors)

      else
        errors << "too many columns - format not understood."
      end

      # One check for every in-and-out shape rather than only the six-column one.
      # The four- and five-column forms roll a backwards shift to the next
      # morning, so only equal times can still reach here -- and `crow,dirt,
      # 0800,0800`, a repeated field, used to save a zero-minute timesheet while
      # the six-column spelling of the same mistake was refused.
      if action == :inout && signin && signout && signin >= signout
        errors << "sign in time starts on or after sign out"
      end

      [action, signin, signout, position, errors]
    end

    # Check the parsed action against the person's current duty state. Returns
    # [open timesheet, signin, errors] -- signin comes back set to the open
    # entry's start time for a sign out, so the review table can show it.
    def validate_timesheet_state(person_id, action, signin, signout)
      errors = []
      timesheet = Timesheet.find_person_on_duty(person_id)

      if action == :in
        if timesheet
          errors << "is on duty"
        else
          # A shift cannot start later than now: the entry is left open, and
          # on_duty_now filters on off_duty alone, so a date typed a week out
          # puts the Ranger on the On Duty board this minute and leaves a live
          # shift no one thinks to close.
          errors << "starts in the future" if signin && signin > Current.time

          # find_person_on_duty is scoped to the current year, so a Ranger left
          # open from a past event reads as off duty here and would quietly get
          # a SECOND open row. The stale one cannot be closed from this page --
          # that is Mass Sign-Out's job -- but it must not be built on either.
          errors << "has a shift still open from a past event" if stale_open_shift?(person_id)

          # :inout runs an overlap check and :in did not, so a back-dated sign in
          # could open a shift inside one the Ranger has already finished. An
          # open shift has no end, so the instant it starts is what has to be
          # clear.
          if signin && Timesheet.find_overlap_for_person(person_id, signin, signin)
            errors << "starts inside a shift already on record"
          end
        end
      elsif action == :out
        if timesheet.nil?
          errors << "is not on duty"
        elsif signout && timesheet.on_duty >= signout
          # >=, matching the in-and-out shapes: signing out at the very minute
          # the shift began saves a zero-length timesheet, and the identical
          # typo spelled "crow,dirt,0800,0800" is refused.
          errors << "sign out is at or before the sign in time"
        elsif signout && signout > Current.time
          # A bare time anchors to today, so "crow,2345" typed at 00:15 -- 23:45
          # half an hour ago -- parses as 23 hours ahead, and "sign out follows
          # sign in" happily passes a shift a day too long.
          errors << "sign out is in the future"
        end
      end

      if action == :inout
        overlap = Timesheet.find_overlap_for_person(person_id, signin, signout) if signin && signout

        # find_overlap_for_person cannot see a still-open shift that began before
        # the window: three of its four SQL terms read off_duty, which is NULL on
        # an open row, so only "on_duty falls inside the window" can ever match.
        # A Ranger on duty since 06:00 would take a back-filled 08:00-16:00 entry
        # sitting inside the shift they have not ended yet. The open row is
        # already in hand, so the check costs nothing.
        overlap ||= timesheet if timesheet && signout && signout >= timesheet.on_duty

        if overlap
          # position&. -- the shared schema carries no FK on position_id, so a
          # non-optional belongs_to still reads nil on an orphaned row, and this
          # message would 500 the review page rather than name the clash.
          errors << "overlapping or duplicate timesheet. Position " \
                    "#{overlap.position&.title || "(unknown)"}" \
                    " Start #{format_stamp(overlap.on_duty)} End #{format_stamp(overlap.off_duty)}"
        end
      elsif timesheet
        signin = timesheet.on_duty
      end

      [timesheet, signin, errors]
    end

    # An open shift from any year, which find_person_on_duty's for_year scope
    # cannot see.
    def stale_open_shift?(person_id)
      Timesheet.for_person(person_id).where(off_duty: nil).exists?
    end

    # Resolve the position name to an id and its canonical title, and check the
    # person holds it. A sign out with no position named inherits the position
    # of the entry being closed.
    def resolve_position(name, positions, person_id, timesheet, action)
      errors = []

      if name.present?
        found = positions[name.downcase]

        unless found
          errors << "position '#{name}' not found"
          return [nil, name, errors]
        end

        if person_id && !PersonPosition.have_position?(person_id, found.id)
          errors << "does not hold the position '#{found.title}'"
        end

        return [found.id, found.title, errors]
      end

      # Only a sign out inherits the open entry's position, and the action test
      # is what confines it. Without it, `crow,,08/15,0845,1650` -- a double
      # comma, or a spreadsheet row with an empty position cell -- would take
      # whatever Crow happens to be on duty for right now, skip the
      # have_position? check on the way past, and back-fill a shift credited to
      # a position the operator never typed and never saw offered. The review
      # table would show a title and look right.
      #
      # position&. for the orphaned-row reason above: the title is only shown,
      # so a missing one renders as a dash rather than 500ing the page.
      return [timesheet.position_id, timesheet.position&.title, errors] if timesheet && action == :out

      [nil, nil, errors]
    end

    # The sign out for the two shapes that give a clock time and let the date be
    # inferred: it lands on the sign in's own date, and a shift ending earlier
    # than it starts ends the next morning. Both shapes used to spell this out
    # separately, and the four-column one reached it by formatting today into a
    # string and parsing it straight back -- which also gave one typo two
    # different error messages depending on which shape it was typed in.
    def same_day_signout(signin, value, errors)
      time = parse_time(value, "sign out", errors)
      return nil unless signin && time

      signout = Time.zone.local(signin.year, signin.month, signin.day, time.hour, time.min)
      (signin > signout) ? signout + 1.day : signout
    end

    # Parse a time into today at that time.
    def parse_time(value, name, errors)
      match = TIME_REGEXP.match(value)
      unless match
        errors << "#{name} is not a valid time format [#{value}]"
        return nil
      end

      today = Current.time
      Time.zone.local(today.year, today.month, today.day, match[1].to_i, match[2].to_i)
    end

    # Parse a date and a time into a single timestamp. Never Date.parse or
    # Time.zone.parse: Date.parse("12345") is 2012-12-10 rather than an error,
    # and Time.zone.parse reads "sun" as the next Sunday. The regexps are the
    # only gate, as upstream.
    def parse_date_and_time(date, time, name, errors)
      date_match = DATE_REGEXP.match(date)
      unless date_match
        errors << "#{name} has an invalid date [#{date}]"
        return nil
      end

      year = date_match[3]
      year = year.nil? ? Current.year : expand_year(year)
      month = date_match[1].to_i
      day = date_match[2].to_i

      unless Date.valid_date?(year, month, day)
        errors << "#{name} has an invalid date [#{date}]"
        return nil
      end

      # Date.valid_date? is happy with the year 0 and the year 9999.
      unless year.between?(EARLIEST_YEAR, Current.year + 1)
        errors << "#{name} has a year outside #{EARLIEST_YEAR}–#{Current.year + 1} [#{date}]"
        return nil
      end

      time_match = TIME_REGEXP.match(time)
      unless time_match
        errors << "#{name} has an invalid time [#{time}]"
        return nil
      end

      Time.zone.local(year, month, day, time_match[1].to_i, time_match[2].to_i)
    end

    def expand_year(year)
      (year.length == 2) ? "20#{year}".to_i : year.to_i
    end

    def format_stamp(time)
      time&.strftime(DateTimeHelper::MONTH_DAY_TIME) || "open"
    end

    def persist_entry(entry, user)
      timesheet, event, data = build_write(entry)
      return false unless timesheet

      timesheet.audit_reason = AUDIT_REASON
      return false unless save_timesheet(timesheet, entry)

      # The id of the row this line actually wrote. Until now the entry carried
      # whatever open shift the person happened to have when the line was
      # parsed, which is right for a sign out and misleading for the other two:
      # the admin log named a timesheet the batch never touched, and an auditor
      # correcting "the row this line created" would edit an unrelated shift.
      entry.timesheet_id = timesheet.id

      timesheet.log(event, data.merge(via: TimesheetLog::VIA_BULK_UPLOAD))

      # Deliberately NOT unconfirming the person's timesheets, which every
      # interactive path (ShiftManage) does: upstream's bulk tool leaves the
      # confirmation standing, and that parity was chosen for this port.
      #
      # The inactive -> active conversion, by contrast, IS run -- but only for a
      # sign out, which is the one action here that ends a live shift the way
      # the HQ window and Mass Sign-Out do. An :inout backfills a shift that
      # already happened and converts no one.
      ShiftManage.convert_inactive_to_active(timesheet, user) if entry.action == :out

      true
    end

    # Returns [timesheet, log event, log data], or a bare nil when the entry
    # cannot be written -- which destructures into three nils at the call site,
    # so the caller's `unless timesheet` guard covers both shapes.
    def build_write(entry)
      case entry.action
      when :inout
        [Timesheet.new(person_id: entry.person_id, position_id: entry.position_id,
                       on_duty: entry.signin, off_duty: entry.signout),
         TimesheetLog::CREATED,
         { position_id: entry.position_id, on_duty: entry.signin.to_s, off_duty: entry.signout.to_s }]

      when :in
        entry.signin ||= Current.time
        [Timesheet.new(person_id: entry.person_id, position_id: entry.position_id, on_duty: entry.signin),
         TimesheetLog::SIGNON,
         { position_id: entry.position_id, on_duty: entry.signin.to_s }]

      when :out
        timesheet = Timesheet.find_by(id: entry.timesheet_id)
        # off_duty is re-checked, not just the row's existence: without it a
        # second sign out for the same Ranger -- or an HQ sign out landing
        # between this request's own re-parse and this write -- silently
        # overwrites the real off duty time and logs a second SIGNOFF.
        if timesheet.nil? || timesheet.off_duty.present?
          entry.errors << "is no longer on duty — someone else signed this shift out. " \
                          "Remove this line and check the list again."
          return nil
        end

        entry.signout ||= Current.time
        timesheet.off_duty = entry.signout
        [timesheet, TimesheetLog::SIGNOFF, { off_duty: entry.signout.to_s }]
      end
    end

    # The house spelling for a system-created entry (see TimesheetMissingReview):
    # the additional_notes validation asks the person for a reason, which has no
    # meaning here, so it is dropped while every other validation still applies.
    def save_timesheet(timesheet, entry)
      timesheet.valid?
      timesheet.errors.delete(:additional_notes)

      if timesheet.errors.any?
        entry.errors.concat(timesheet.errors.full_messages)
        return false
      end

      return true if timesheet.save(validate: false)

      # save returns false rather than raising when a before_save throws :abort.
      # None does today, but this is the single return value the all-or-nothing
      # promise rests on -- discarding it would report a batch as applied having
      # written nothing.
      entry.errors << "could not be saved"
      false
    end
  end
end
