# frozen_string_literal: true

require "test_helper"

class BulkSignInOutTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
  include TimesheetAdminTestHelper

  # A Thursday inside the current event year, so "today" is stable and the
  # graveyard rollovers land on a known date.
  NOW = Time.zone.local(2026, 8, 13, 12, 0, 0)

  setup do
    travel_to NOW
    Rails.cache.clear
    Current.reset

    @person = person(:active_ranger)
    @operator = person(:auditor_ranger)
    Current.person = @operator

    @position = create_position!("Site Setup")
    @other_position = create_position!("Intercept")
    grant_position(@position)
    grant_position(@other_position)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- column shapes ---

  test "two columns with a position signs in now" do
    entry = parse_one("#{@person.callsign},Site Setup")

    assert_empty entry.errors
    assert_equal :in, entry.action
    assert_equal @position.id, entry.position_id
    assert_equal "Site Setup", entry.position_title
    assert_nil entry.signin, "an immediate sign in has no parsed time until it is written"
    assert_nil entry.signout
  end

  test "two columns with a time signs out" do
    open_shift!(on_duty: Time.zone.local(2026, 8, 13, 6, 0))

    entry = parse_one("#{@person.callsign},0730")

    assert_empty entry.errors
    assert_equal :out, entry.action
    assert_equal Time.zone.local(2026, 8, 13, 7, 30), entry.signout
  end

  test "three columns with a date signs out at that date and time" do
    open_shift!(on_duty: Time.zone.local(2026, 8, 12, 6, 0))

    entry = parse_one("#{@person.callsign},08/12,2200")

    assert_empty entry.errors
    assert_equal :out, entry.action
    assert_equal Time.zone.local(2026, 8, 12, 22, 0), entry.signout
  end

  test "three columns with a position signs in at a time today" do
    entry = parse_one("#{@person.callsign},Site Setup,0845")

    assert_empty entry.errors
    assert_equal :in, entry.action
    assert_equal Time.zone.local(2026, 8, 13, 8, 45), entry.signin
  end

  test "four columns with two times signs in and out today" do
    entry = parse_one("#{@person.callsign},Site Setup,0845,1650")

    assert_empty entry.errors
    assert_equal :inout, entry.action
    assert_equal Time.zone.local(2026, 8, 13, 8, 45), entry.signin
    assert_equal Time.zone.local(2026, 8, 13, 16, 50), entry.signout
  end

  # A sign in leaves the shift open, so its date must already have happened --
  # every :in case here is back-dated for that reason.
  test "four columns with a date signs in at that date and time" do
    entry = parse_one("#{@person.callsign},Site Setup,08/11,0845")

    assert_empty entry.errors
    assert_equal :in, entry.action
    assert_equal Time.zone.local(2026, 8, 11, 8, 45), entry.signin
  end

  test "five columns signs in and out ending the same day" do
    entry = parse_one("#{@person.callsign},Site Setup,08/18,0845,1650")

    assert_empty entry.errors
    assert_equal :inout, entry.action
    assert_equal Time.zone.local(2026, 8, 18, 8, 45), entry.signin
    assert_equal Time.zone.local(2026, 8, 18, 16, 50), entry.signout
  end

  test "six columns signs in and out across days" do
    entry = parse_one("#{@person.callsign},Intercept,08/15,2345,08/16,0630")

    assert_empty entry.errors
    assert_equal :inout, entry.action
    assert_equal Time.zone.local(2026, 8, 15, 23, 45), entry.signin
    assert_equal Time.zone.local(2026, 8, 16, 6, 30), entry.signout
  end

  test "one column is too few" do
    entry = parse_one(@person.callsign)

    assert_includes entry.errors.first, "too few columns"
  end

  test "seven columns is too many" do
    entry = parse_one("#{@person.callsign},Site Setup,08/15,2345,08/16,0630,extra")

    assert_includes entry.errors.first, "too many columns"
  end

  test "a trailing comma is a real empty column, not a shorter line" do
    # Ruby's plain split would drop the empty field and silently read this as
    # the three-column sign in the reader did not type.
    entry = parse_one("#{@person.callsign},Site Setup,0845,")

    assert_equal :inout, entry.action
    assert(entry.errors.any? { |error| error.include?("sign out") })
  end

  # --- graveyard rollover ---

  test "four column shift ending before it starts rolls the sign out to the next day" do
    entry = parse_one("#{@person.callsign},Intercept,2345,0630")

    assert_empty entry.errors
    assert_equal Time.zone.local(2026, 8, 13, 23, 45), entry.signin
    assert_equal Time.zone.local(2026, 8, 14, 6, 30), entry.signout
  end

  test "five column shift ending before it starts rolls the sign out to the next day" do
    entry = parse_one("#{@person.callsign},Intercept,08/15,2345,0630")

    assert_empty entry.errors
    assert_equal Time.zone.local(2026, 8, 15, 23, 45), entry.signin
    assert_equal Time.zone.local(2026, 8, 16, 6, 30), entry.signout
  end

  test "six column form does not roll over and refuses a backwards shift" do
    entry = parse_one("#{@person.callsign},Intercept,08/15,2345,08/15,0630")

    assert_includes entry.errors, "sign in time starts on or after sign out"
  end

  test "six column form refuses an identical sign in and sign out" do
    entry = parse_one("#{@person.callsign},Intercept,08/15,0800,08/15,0800")

    assert_includes entry.errors, "sign in time starts on or after sign out"
  end

  # --- date and time parsing ---

  test "a two digit year expands to the twenty-first century" do
    entry = parse_one("#{@person.callsign},Site Setup,08/11/26,0845")

    assert_empty entry.errors
    assert_equal 2026, entry.signin.year
  end

  test "a year outside the plausible range is refused at both ends" do
    # Date.valid_date? accepts the year 0 and the year 9999; MariaDB's DATETIME
    # floor does not, and the save would raise mid-commit rather than landing in
    # the review table. "08/15/98" is the two-digit trap: it expands to 2098.
    ["#{@person.callsign},Site Setup,08/11/0000,0845",
     "#{@person.callsign},Site Setup,08/11/98,0845,1650"].each do |line|
      assert(parse_one(line).errors.any? { |error| error.include?("year outside") },
             "#{line} should be refused")
    end
  end

  test "a four digit year is used as given" do
    entry = parse_one("#{@person.callsign},Site Setup,08/18/2025,0845")

    assert_empty entry.errors
    assert_equal 2025, entry.signin.year
  end

  test "a missing year defaults to the current year" do
    entry = parse_one("#{@person.callsign},Site Setup,08/11,0845")

    assert_empty entry.errors
    # The literal, not Current.year -- mirroring the implementation's own
    # expression would leave this green if the code stopped reading Current.
    assert_equal 2026, entry.signin.year
  end

  test "dashes work as date separators" do
    entry = parse_one("#{@person.callsign},Site Setup,08-11,0845")

    assert_empty entry.errors
    assert_equal Time.zone.local(2026, 8, 11, 8, 45), entry.signin
  end

  test "a colon is optional in a time" do
    entry = parse_one("#{@person.callsign},Site Setup,08:45")

    assert_empty entry.errors
    assert_equal Time.zone.local(2026, 8, 13, 8, 45), entry.signin
  end

  test "an impossible calendar date is refused" do
    entry = parse_one("#{@person.callsign},Site Setup,02/30,0845")

    assert(entry.errors.any? { |error| error.include?("invalid date") })
  end

  test "a month above twelve is refused" do
    entry = parse_one("#{@person.callsign},Site Setup,13/01,0845")

    assert(entry.errors.any? { |error| error.include?("invalid date") })
  end

  test "an out of range time is refused" do
    entry = parse_one("#{@person.callsign},Site Setup,2400")

    assert(entry.errors.any? { |error| error.include?("not a valid time") })
  end

  test "an out of range minute is refused" do
    entry = parse_one("#{@person.callsign},Site Setup,0761")

    assert(entry.errors.any? { |error| error.include?("not a valid time") })
  end

  test "a run of digits is not silently read as a date" do
    # Date.parse("12345") is 2012-12-10 rather than an error, which is why the
    # regexp is the only gate here.
    entry = parse_one("#{@person.callsign},Site Setup,12345,0845")

    assert(entry.errors.any? { |error| error.include?("invalid date") })
  end

  test "the 007 position is a position and not a time" do
    position = create_position!("007")
    grant_position(position)

    entry = parse_one("#{@person.callsign},007")

    assert_empty entry.errors
    assert_equal :in, entry.action
    assert_equal position.id, entry.position_id
  end

  # --- people, positions, and duty state ---

  test "an unknown callsign is refused" do
    entry = parse_one("nosuchranger,Site Setup")

    assert_includes entry.errors, "callsign 'nosuchranger' not found"
  end

  test "a callsign is echoed back in its canonical spelling" do
    entry = parse_one("#{@person.callsign.upcase},Site Setup")

    assert_equal @person.callsign, entry.callsign
    assert_equal @person.id, entry.person_id
  end

  test "an unknown position is refused" do
    entry = parse_one("#{@person.callsign},Gate")

    assert_includes entry.errors, "position 'Gate' not found"
  end

  test "a position the person does not hold is refused" do
    unheld = create_position!("Tow Truck")

    entry = parse_one("#{@person.callsign},Tow Truck")

    assert_includes entry.errors, "does not hold the position 'Tow Truck'"
    assert_equal unheld.id, entry.position_id
  end

  test "a position matches regardless of case" do
    entry = parse_one("#{@person.callsign},sItE sEtUp")

    assert_empty entry.errors
    assert_equal @position.id, entry.position_id
  end

  test "signing in someone already on duty is refused" do
    open_shift!

    entry = parse_one("#{@person.callsign},Site Setup")

    assert_includes entry.errors, "is on duty"
  end

  test "signing out someone who is not on duty is refused" do
    entry = parse_one("#{@person.callsign},0730")

    assert_includes entry.errors, "is not on duty"
  end

  test "a sign out before the shift started is refused" do
    open_shift!(on_duty: Time.zone.local(2026, 8, 13, 9, 0))

    entry = parse_one("#{@person.callsign},0730")

    assert_includes entry.errors, "sign out is at or before the sign in time"
  end

  test "a sign out at the very minute the shift started is refused" do
    # The zero-length shift the in-and-out shapes already refuse; reading the
    # start time off the On Duty board by mistake is how it gets typed.
    open_shift!(on_duty: Time.zone.local(2026, 8, 13, 8, 0))

    entry = parse_one("#{@person.callsign},0800")

    assert_includes entry.errors, "sign out is at or before the sign in time"
  end

  test "a sign out in the future is refused" do
    # "crow,2345" typed just after midnight means 23:45 half an hour ago, but a
    # bare time anchors to today and would book a shift a day too long.
    open_shift!(on_duty: Time.zone.local(2026, 8, 13, 6, 0))

    entry = parse_one("#{@person.callsign},2345")

    assert_includes entry.errors, "sign out is in the future"
  end

  test "a sign in dated in the future is refused" do
    entry = parse_one("#{@person.callsign},Site Setup,08/18,0845")

    assert_includes entry.errors, "starts in the future"
  end

  test "a sign in starting inside a shift already on record is refused" do
    Timesheet.create!(person_id: @person.id, position_id: @position.id,
                      on_duty: Time.zone.local(2026, 8, 11, 8, 0),
                      off_duty: Time.zone.local(2026, 8, 11, 16, 0),
                      additional_notes: "fixture")

    entry = parse_one("#{@person.callsign},Site Setup,08/11,0900")

    assert_includes entry.errors, "starts inside a shift already on record"
  end

  test "a sign in is refused while a shift from a past event is still open" do
    # find_person_on_duty is year-scoped, so this row is invisible to it -- and
    # a second open row is worse than refusing to add one.
    Timesheet.create!(person_id: @person.id, position_id: @position.id,
                      on_duty: Time.zone.local(2024, 8, 20, 8, 0),
                      additional_notes: "never closed")

    entry = parse_one("#{@person.callsign},Site Setup")

    assert_includes entry.errors, "has a shift still open from a past event"
  end

  test "a sign out shows the open entry's start time and position" do
    timesheet = open_shift!(on_duty: Time.zone.local(2026, 8, 13, 6, 15))

    entry = parse_one("#{@person.callsign},0730")

    assert_empty entry.errors
    assert_equal timesheet.id, entry.timesheet_id
    assert_equal timesheet.on_duty, entry.signin
    assert_equal @position.title, entry.position_title
    assert_equal @position.id, entry.position_id
  end

  test "an overlapping shift is refused and the overlap is named" do
    Timesheet.create!(person_id: @person.id, position_id: @position.id,
                      on_duty: Time.zone.local(2026, 8, 18, 8, 0),
                      off_duty: Time.zone.local(2026, 8, 18, 17, 0),
                      additional_notes: "fixture")

    entry = parse_one("#{@person.callsign},Intercept,08/18,0900,1000")

    assert(entry.errors.any? { |error| error.include?("overlapping or duplicate timesheet") })
    assert(entry.errors.any? { |error| error.include?(@position.title) })
  end

  test "a sign in with an empty position is refused rather than failing at commit" do
    entry = parse_one("#{@person.callsign},")

    assert_includes entry.errors, "position not specified"
  end

  test "an in-and-out with an empty position does not borrow the open shift's position" do
    # A double comma, or a spreadsheet row with an empty position cell. The open
    # entry's position must not be adopted silently -- doing so also skips the
    # held-position check, and the review table would show a title that looks
    # deliberate.
    # The window sits before the open shift began, so the overlap rule stays out
    # of the way and the position is the only thing wrong with this line.
    open_shift!(position: @other_position, on_duty: Time.zone.local(2026, 8, 13, 6, 0))

    entry = parse_one("#{@person.callsign},,08/11,0845,1650")

    assert_includes entry.errors, "position not specified"
    assert_nil entry.position_id
  end

  test "a sign out still inherits the open shift's position" do
    open_shift!(position: @other_position, on_duty: Time.zone.local(2026, 8, 13, 6, 0))

    entry = parse_one("#{@person.callsign},0730")

    assert_empty entry.errors
    assert_equal @other_position.id, entry.position_id
  end

  test "a zero-length shift is refused in every in-and-out shape" do
    ["#{@person.callsign},Site Setup,0800,0800",
     "#{@person.callsign},Site Setup,08/18,0800,0800",
     "#{@person.callsign},Site Setup,08/18,0800,08/18,0800"].each do |line|
      assert_includes parse_one(line).errors, "sign in time starts on or after sign out",
                      "#{line} should not create a zero-minute timesheet"
    end
  end

  test "a three digit year is refused rather than building a year 202 timesheet" do
    # The review table prints no year, so nothing downstream would show this.
    entry = parse_one("#{@person.callsign},Site Setup,08/18/202,0845")

    assert(entry.errors.any? { |error| error.include?("invalid date") })
  end

  test "an in-and-out overlapping a still-open shift is refused" do
    # find_overlap_for_person is NULL-unsafe for an open row, so this relies on
    # the open entry that validate_timesheet_state already has in hand.
    open_shift!(on_duty: Time.zone.local(2026, 8, 13, 6, 0))

    entry = parse_one("#{@person.callsign},Intercept,08/13,0800,1600")

    assert(entry.errors.any? { |error| error.include?("overlapping or duplicate timesheet") })
  end

  test "an in-and-out that ends before a still-open shift began is allowed" do
    open_shift!(on_duty: Time.zone.local(2026, 8, 13, 6, 0))

    entry = parse_one("#{@person.callsign},Intercept,08/11,0800,1600")

    assert_empty entry.errors
  end

  # --- the line list itself ---

  test "blank and whitespace-only lines are skipped" do
    entries, have_error = BulkSignInOut.parse(
      "#{@person.callsign},Site Setup\n\n   \n#{person(:alpha_ranger).callsign},Site Setup\n"
    )

    assert_equal 2, entries.size
    assert have_error, "the alpha does not hold the position"
  end

  test "parse reports have_error only when a line carries one" do
    _entries, have_error = BulkSignInOut.parse("#{@person.callsign},Site Setup")

    assert_not have_error
  end

  test "a line missing its callsign is refused" do
    entry = parse_one(",Site Setup")

    assert_includes entry.errors, "Callsign not specified"
    assert_equal :unknown, entry.action
  end

  test "carriage returns from a browser textarea are stripped" do
    entries, have_error = BulkSignInOut.parse("#{@person.callsign},Site Setup\r\n")

    assert_not have_error, entries.first.errors.inspect
    assert_equal 1, entries.size
  end

  # --- process ---

  test "process creates a completed entry for a sign in and out" do
    entries, = BulkSignInOut.parse("#{@person.callsign},Site Setup,08/18,0845,1650")

    assert_not BulkSignInOut.process(entries, user: @operator)

    entry = Timesheet.for_person(@person.id).order(:id).last
    assert_equal Time.zone.local(2026, 8, 18, 8, 45), entry.on_duty
    assert_equal Time.zone.local(2026, 8, 18, 16, 50), entry.off_duty
    assert_equal @position.id, entry.position_id
    assert_log entry, TimesheetLog::CREATED
  end

  test "process starts a shift for a sign in and stamps now when no time was given" do
    entries, = BulkSignInOut.parse("#{@person.callsign},Site Setup")

    assert_not BulkSignInOut.process(entries, user: @operator)

    entry = Timesheet.find_person_on_duty(@person.id)
    assert_not_nil entry
    assert_equal NOW, entry.on_duty
    assert_equal NOW, entries.first.signin, "the review table shows the time actually written"
    assert_log entry, TimesheetLog::SIGNON
  end

  test "process closes the open entry for a sign out" do
    timesheet = open_shift!(on_duty: Time.zone.local(2026, 8, 13, 6, 15))
    entries, = BulkSignInOut.parse("#{@person.callsign},0730")

    assert_not BulkSignInOut.process(entries, user: @operator)

    timesheet.reload
    assert_equal Time.zone.local(2026, 8, 13, 7, 30), timesheet.off_duty
    assert_log timesheet, TimesheetLog::SIGNOFF
  end

  test "process records the id of the row it actually wrote" do
    entries, = BulkSignInOut.parse("#{@person.callsign},Site Setup,08/18,0845,1650")
    BulkSignInOut.process(entries, user: @operator)

    written = Timesheet.for_person(@person.id).order(:id).last
    assert_equal written.id, entries.first.timesheet_id,
                 "the admin log names this id -- it must be the row the line created"
  end

  # Named for what it asserts. The write also sets audit_reason, but Timesheet
  # does not set audit_model, so that assignment records nothing anywhere --
  # claiming it in the name of this test would hide that.
  test "process marks the write as having come from the bulk uploader" do
    entries, = BulkSignInOut.parse("#{@person.callsign},Site Setup,08/18,0845,1650")
    BulkSignInOut.process(entries, user: @operator)

    entry = Timesheet.for_person(@person.id).order(:id).last
    log = TimesheetLog.find_by(timesheet_id: entry.id, action: TimesheetLog::CREATED)

    assert_equal TimesheetLog::VIA_BULK_UPLOAD, log.decode_data["via"]
  end

  test "process skips entries carrying errors" do
    entries, = BulkSignInOut.parse("nosuchranger,Site Setup\n#{@person.callsign},Site Setup")

    assert_difference "Timesheet.count", 1 do
      BulkSignInOut.process(entries, user: @operator)
    end
  end

  test "process reports a save failure on the entry instead of raising" do
    entries, = BulkSignInOut.parse("#{@person.callsign},Site Setup,08/18,0845,1650")
    entries.first.signin = nil

    assert BulkSignInOut.process(entries, user: @operator)
    assert entries.first.errors.any?
  end

  test "a save failure rolls back the lines that had already been written" do
    # The good line is first, so a commit that does not roll back would leave it
    # behind while the page tells the operator nothing was saved.
    # Granted before parsing -- an entry that fails its checks is skipped by
    # process, so it would never reach the write that this test needs to fail.
    grant_position(@position, person: person(:alpha_ranger))
    entries, = BulkSignInOut.parse(
      "#{@person.callsign},Site Setup,08/18,0845,1650\n" \
      "#{person(:alpha_ranger).callsign},Site Setup,08/19,0845,1650"
    )
    entries.last.signin = nil

    # Without this the count assertion is equally satisfied by the good line
    # having errored and been skipped -- the premise is that it was written and
    # then undone.
    assert_empty entries.first.errors

    assert_no_difference "Timesheet.count" do
      assert BulkSignInOut.process(entries, user: @operator)
    end
  end

  # --- lines checked against each other, not only against the database ---

  test "the same sign in twice does not create two open shifts" do
    entries, have_error = BulkSignInOut.parse(
      "#{@person.callsign},Site Setup\n#{@person.callsign},Site Setup"
    )

    # have_error is what the controller refuses the whole batch on, so nothing
    # reaches the database. process itself would still write the clean first
    # line -- the all-or-nothing rule lives one level up.
    assert have_error
    assert_empty entries.first.errors, "the first line is the one that stands"
    assert(entries.last.errors.any? { |error| error.include?("another line above") })
  end

  test "two overlapping in-and-outs for one Ranger are refused" do
    entries, = BulkSignInOut.parse(
      "#{@person.callsign},Site Setup,08/11,0800,1600\n" \
      "#{@person.callsign},Intercept,08/11,1000,1800"
    )

    assert(entries.last.errors.any? { |error| error.include?("another line above") })
  end

  test "two shifts that do not overlap are both allowed" do
    entries, have_error = BulkSignInOut.parse(
      "#{@person.callsign},Site Setup,08/11,0800,1200\n" \
      "#{@person.callsign},Intercept,08/11,1200,1600"
    )

    assert_not have_error, entries.map(&:errors).inspect
  end

  test "the same Ranger signed out twice is refused" do
    open_shift!(on_duty: Time.zone.local(2026, 8, 13, 6, 0))

    entries, = BulkSignInOut.parse("#{@person.callsign},0700\n#{@person.callsign},0800")

    assert(entries.last.errors.any? { |error| error.include?("another line above") })
  end

  test "two different Rangers never conflict with each other" do
    other = person(:alpha_ranger)
    grant_position(@position, person: other)

    entries, have_error = BulkSignInOut.parse(
      "#{@person.callsign},Site Setup\n#{other.callsign},Site Setup"
    )

    assert_not have_error, entries.map(&:errors).inspect
  end

  test "a paste longer than the cap is refused" do
    lines = Array.new(BulkSignInOut::MAX_LINES + 5) { "#{@person.callsign},Site Setup" }

    entries, have_error = BulkSignInOut.parse(lines.join("\n"))

    assert have_error
    assert_equal BulkSignInOut::MAX_LINES, entries.size
    assert(entries.last.errors.any? { |error| error.include?("split the list") })
  end

  # --- decision 2: confirmation is left standing ---

  test "a bulk write leaves the person's timesheet confirmation alone" do
    confirm_timesheet_for(@person, Current.year)
    entries, = BulkSignInOut.parse("#{@person.callsign},Site Setup,08/18,0845,1650")

    BulkSignInOut.process(entries, user: @operator)

    event = PersonEvent.first_or_new_for_person_year(@person.id, Current.year)
    assert event.timesheet_confirmed, "upstream parity: bulk writes do not unconfirm"
  end

  # --- decision 3: an inactive Ranger signed out is converted back to active ---

  test "signing an inactive Ranger out converts them back to active" do
    inactive = person(:inactive_ranger)
    grant_position(@position, person: inactive)
    open_shift!(person: inactive)
    entries, = BulkSignInOut.parse("#{inactive.callsign},1130")

    assert_emails 1 do
      perform_enqueued_jobs do
        BulkSignInOut.process(entries, user: @operator)
      end
    end

    assert_equal Person::ACTIVE, inactive.reload.status
  end

  test "signing an inactive Ranger out of a training shift does not convert them" do
    inactive = person(:inactive_ranger)
    training = create_position!("Green Dot Training", type: Position::TYPE_TRAINING)
    grant_position(training, person: inactive)
    open_shift!(person: inactive, position: training)
    entries, = BulkSignInOut.parse("#{inactive.callsign},1130")

    # Without this the sign out could be refused for some unrelated reason and
    # the status assertion below would hold for the wrong one.
    assert_empty entries.first.errors
    assert_not BulkSignInOut.process(entries, user: @operator)

    assert_equal Person::INACTIVE, inactive.reload.status
  end

  test "backfilling a completed shift for an inactive Ranger does not convert them" do
    inactive = person(:inactive_ranger)
    grant_position(@position, person: inactive)
    entries, = BulkSignInOut.parse("#{inactive.callsign},Site Setup,08/18,0845,1650")

    BulkSignInOut.process(entries, user: @operator)

    assert_equal Person::INACTIVE, inactive.reload.status,
                 "an :inout records history rather than ending a live shift"
  end

  private

  def parse_one(line)
    entries, = BulkSignInOut.parse(line)
    entries.first
  end

  def create_position!(title, **attrs)
    Position.create!({ title: title, active: true, no_training_required: true }.merge(attrs))
  end

  def grant_position(position, person: @person)
    PersonPosition.find_or_create_by!(person_id: person.id, position_id: position.id)
  end

  def open_shift!(person: @person, position: @position, on_duty: NOW - 2.hours)
    Timesheet.create!(person_id: person.id, position_id: position.id,
                      on_duty: on_duty, additional_notes: "test shift")
  end

  def assert_log(timesheet, action)
    assert TimesheetLog.exists?(timesheet_id: timesheet.id, action: action),
           "expected a #{action} log for timesheet #{timesheet.id}"
  end
end
