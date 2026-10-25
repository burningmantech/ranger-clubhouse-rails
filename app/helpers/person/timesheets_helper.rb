# frozen_string_literal: true

# Display labels for the person timesheet audit log — ports of the Ember
# timesheet-log component's action labels and blocker audit labels.
module Person::TimesheetsHelper
  TIMESHEET_LOG_ACTION_LABELS = {
    TimesheetLog::SIGNON => "Shift started",
    TimesheetLog::SIGNOFF => "Shift ended",
    TimesheetLog::UPDATE => "Updated",
    TimesheetLog::DELETE => "Deleted",
    TimesheetLog::DELETE_MISTAKE => "Deleted (accidental creation)",
    TimesheetLog::CONFIRMED => "Entire timesheet confirmed",
    TimesheetLog::UNCONFIRMED => "Entire timesheet unconfirmed",
    TimesheetLog::UNVERIFIED => "Unverified",
    TimesheetLog::VERIFY => "Verified",
    TimesheetLog::CREATED => "Created"
  }.freeze

  TIMESHEET_LOG_VIA_LABELS = {
    TimesheetLog::VIA_BULK_UPLOAD => "bulk uploader",
    TimesheetLog::VIA_MISSING_ENTRY => "missing entry request"
  }.freeze

  TIMESHEET_BLOCKER_LABELS = {
    Timesheet::BLOCKED_NOT_CHEETAH_CUB => "Retired or inactive extension status signing into a non-Cheetah-Cub shift",
    Timesheet::BLOCKED_NOT_TRAINED => "Has not completed training",
    Timesheet::BLOCKED_NO_BURN_PERIMETER_EXP => "No recent burn perimeter experience",
    Timesheet::BLOCKED_NO_EMPLOYEE_ID => "No employee id on file for a paid position",
    Timesheet::BLOCKED_TOO_EARLY => "Attempted to sign in too early",
    Timesheet::BLOCKED_TOO_LATE => "Attempted to sign in too late",
    Timesheet::BLOCKED_UNSIGNED_SANDMAN_AFFIDAVIT => "Sandman Affidavit not signed",
    Timesheet::BLOCKED_IS_RETIRED => "Is retired"
  }.freeze

  def timesheet_log_action_label(action)
    TIMESHEET_LOG_ACTION_LABELS[action] || action
  end

  def timesheet_log_via_label(via)
    TIMESHEET_LOG_VIA_LABELS[via] || via
  end

  # Accepts both provenances: string-keyed audit-log JSON and symbol-keyed
  # hashes fresh from SignInBlocker.
  #
  # Which check fired is only half the answer -- an HQ lead deciding whether to
  # force a start, and whoever reviews that decision afterwards, both need to
  # know by how much. Everything SignInBlocker recorded about the trigger is
  # spelled out after the label; blockers that carry no detail keep the bare
  # label, as do the older logs written before a field existed.
  def timesheet_blocker_label(blocker)
    blocker = blocker.deep_stringify_keys
    label = TIMESHEET_BLOCKER_LABELS[blocker["blocker"]] || blocker["blocker"]
    label += " - #{blocker.dig("position", "title")}" if blocker["position"].present?
    detail = timesheet_blocker_detail(blocker)

    detail.present? ? "#{label} — #{detail}" : label
  end

  def timesheet_status_icon(entry)
    if entry.off_duty.nil?
      fa_icon "person-walking", :solid
    elsif entry.status_verified?
      fa_icon "check", :solid, class: "icon-success"
    elsif entry.status_approved?
      fa_icon "thumbs-up", :regular
    elsif entry.status_pending?
      fa_icon "arrow-right", :solid, class: "icon-error"
    elsif entry.status_rejected?
      fa_icon "xmark", :solid
    else
      fa_icon "question", :solid
    end
  end

  def timesheet_status_badges(entry)
    if entry.off_duty.nil?
      ui_badge "Still On Duty", :warning
    elsif entry.status_verified?
      ui_badge "Verified", :success
    elsif entry.status_approved?
      safe_join([ui_badge("Correction Approved", :success),
                 content_tag(:div, ui_badge("Verification still needed", :secondary), class: "mt-1")])
    elsif entry.status_pending?
      ui_badge "Correction Requested", :error
    elsif entry.status_rejected?
      ui_badge "Correction Rejected", :warning
    else
      ui_badge "Unverified", :secondary
    end
  end

  def missing_request_status_icon(request)
    if request.status_pending?
      fa_icon "arrow-right", :solid, class: "icon-error"
    elsif request.status_approved?
      fa_icon "check", :solid, class: "icon-success"
    else
      fa_icon "xmark", :solid
    end
  end

  def missing_request_status_badge(request)
    if request.status_pending?
      ui_badge "Review needed", :warning
    elsif request.status_approved?
      ui_badge "Approved", :success
    else
      ui_badge "Request rejected", :error
    end
  end

  # --- Entries table filters -------------------------------------------------
  #
  # The entries table narrows on five questions, each a select whose values ride
  # in the URL. The labels live here because the chips, the selects and the
  # tests below all have to agree about what a value means; the controller reads
  # them inside methods, never from its class body, so neither autoload waits on
  # the other.

  # Still on duty is not a review status, but it is what the row's badge says,
  # so it is what the select has to offer.
  ON_DUTY_FILTER = "onduty"

  TIMESHEET_STATUS_FILTER_LABELS = {
    ON_DUTY_FILTER => "Still On Duty",
    Timesheet::STATUS_PENDING => "Correction Requested",
    Timesheet::STATUS_APPROVED => "Correction Approved",
    Timesheet::STATUS_REJECTED => "Correction Rejected",
    Timesheet::STATUS_VERIFIED => "Verified",
    Timesheet::STATUS_UNVERIFIED => "Unverified"
  }.freeze

  TOO_SHORT_FILTER = "too-short"
  TOO_LONG_FILTER = "too-long"
  OVERLAPPING_FILTER = "overlapping"

  TIMESHEET_ISSUE_FILTER_LABELS = {
    TOO_SHORT_FILTER => "Too Short",
    TOO_LONG_FILTER => "Too Long",
    OVERLAPPING_FILTER => "Overlapping"
  }.freeze

  YES_FILTER = "yes"
  NO_FILTER = "no"

  TIMESHEET_ECHELON_FILTER_LABELS = { YES_FILTER => "Yes", NO_FILTER => "No" }.freeze
  TIMESHEET_COUNTED_FILTER_LABELS = { YES_FILTER => "Counted", NO_FILTER => "Not Counted" }.freeze

  # What each filter is called, on its select and on its chip -- one name, so
  # the chip a reader removes is recognisably the select they set.
  TIMESHEET_FILTER_NAMES = {
    status: "Status",
    position_id: "Position",
    issue: "Flagged",
    echelon: "Echelon Volunteer",
    counted: "Appreciation Hours"
  }.freeze

  # Only where the name alone does not say what is being asked.
  TIMESHEET_FILTER_HELP_TEXT = {
    issue: "Entries the table marks as suspiciously short or long, or overlapping another entry.",
    counted: "Whether the position's hours count toward provisions."
  }.freeze

  # Every choice each select offers, value to label. Positions come from the
  # year's own entries -- the whole position list would mostly be choices that
  # can only return an empty table.
  def timesheet_filter_labels(entries)
    {
      status: TIMESHEET_STATUS_FILTER_LABELS,
      position_id: timesheet_position_filter_labels(entries),
      issue: TIMESHEET_ISSUE_FILTER_LABELS,
      echelon: TIMESHEET_ECHELON_FILTER_LABELS,
      counted: TIMESHEET_COUNTED_FILTER_LABELS
    }
  end

  # String keys: a URL parameter is a string, and the sentinel it is compared
  # against is one too.
  def timesheet_position_filter_labels(entries)
    entries.map { |entry| [entry.position_id.to_s, entry.position.title] }
           .uniq.sort_by(&:last).to_h
  end

  # Does the entry belong under this choice? One place for all five, so a label
  # above and the test that honours it cannot drift apart.
  def timesheet_entry_matches?(entry, key, value, overlapping_ids)
    case key
    when :status then timesheet_status_filter_value(entry) == value
    when :position_id then entry.position_id == value.to_i
    when :issue then timesheet_issue_filter_values(entry, overlapping_ids).include?(value)
    when :echelon then entry.is_echelon == (value == YES_FILTER)
    when :counted then entry.position.count_hours == (value == YES_FILTER)
    else false
    end
  end

  # The one status the row's badge shows. On duty outranks the review status,
  # exactly as the badge does, so the counts add up to the table and choosing
  # "Unverified" never turns up a row labelled something else.
  def timesheet_status_filter_value(entry)
    return ON_DUTY_FILTER if entry.off_duty.nil?
    return entry.review_status if TIMESHEET_STATUS_FILTER_LABELS.key?(entry.review_status)

    Timesheet::STATUS_UNVERIFIED
  end

  # Every problem flagged on the row, not just the first: an overlap and a
  # suspicious length are different faults and a row can carry both. The
  # duration checks follow the table's own guards -- an entry still on duty has
  # no final length, and a suppressed warning is one a reviewer has dismissed --
  # so a choice returns precisely the rows showing that warning.
  def timesheet_issue_filter_values(entry, overlapping_ids)
    values = []
    values << OVERLAPPING_FILTER if overlapping_ids.include?(entry.id)
    return values if entry.off_duty.nil? || entry.suppress_duration_warning

    values << TOO_SHORT_FILTER if timesheet_too_short?(entry)
    values << TOO_LONG_FILTER if timesheet_too_long?(entry)
    values
  end

  # One removable chip per applied filter; each URL drops just that one and
  # keeps the year, which is not a filter and must survive every chip.
  def timesheet_filter_chips(filters, labels, person, year)
    active = UiComponents::FilterBarHelper.active_filters(filters)

    filter_chips(active, TIMESHEET_FILTER_NAMES,
                 value_label: ->(key, value) { labels.dig(key, value) || value }) do |remaining|
      person_timesheets_path(person, year:, **remaining)
    end
  end

  def timesheet_too_short?(entry)
    entry.too_short?
  end

  # Over 1.5x the scheduled shift length counts as suspiciously long.
  def timesheet_too_long?(entry)
    entry.slot.present? && entry.duration > timesheet_slot_duration(entry.slot) * 1.5
  end

  def timesheet_slot_duration(slot)
    slot.ends - slot.begins
  end

  private

  # Why the check fired, in the terms the reader is judging it by. Only the
  # blockers that recorded something have detail to give.
  def timesheet_blocker_detail(blocker)
    case blocker["blocker"]
    when Timesheet::BLOCKED_TOO_EARLY
      check_in_timing_detail(blocker, "before", "opens")
    when Timesheet::BLOCKED_TOO_LATE
      check_in_timing_detail(blocker, "after", "closes")
    when Timesheet::BLOCKED_NO_BURN_PERIMETER_EXP
      burn_perimeter_detail(blocker)
    end
  end

  # How far off the check-in was, then the window it missed. SignInBlocker
  # records distance and cutoff in whole minutes.
  #
  # Past a day the span is said in days: hour_minute_words has no day component,
  # and a real 2025 blocker rendered as "670 hours 37 mins", which no reader can
  # place. That far out the slot is nowhere near the shift start printed beside
  # it either, so it has to name its own date to be reconcilable at all.
  def check_in_timing_detail(blocker, direction, gate)
    parts = []
    seconds = blocker["distance"].presence&.to_i&.*(60)
    far = seconds && seconds >= 1.day
    begins = blocker_slot_time(blocker, with_date: far)

    if seconds
      span = hour_minute_words_or_day_format(seconds)
      parts << "#{span} #{direction} the #{"#{begins} " if begins}start"
    elsif begins
      parts << "shift starts at #{begins}"
    end

    if blocker["cutoff"].present?
      parts << "check-in #{gate} #{pluralize(blocker["cutoff"].to_i, "minute")} #{direction} the start"
    end

    parts.join("; ")
  end

  # What was required against what is on record. last_worked is only asserted
  # when the log actually carries the key -- the pre-2025 format never wrote
  # one, and "none on record" would be inventing a fact about those rows.
  def burn_perimeter_detail(blocker)
    parts = []
    within = blocker["within_years"]
    parts << "needs experience within #{pluralize(within.to_i, "year")}" if within.present?

    if blocker.key?("last_worked")
      last = blocker["last_worked"]
      parts << (last.present? ? "last was #{last["title"]} in #{last["year"]}" : "none on record")
    end

    parts.join("; ")
  end

  # The shift's own wall-clock start. slot.begins is stored as local wall-clock
  # already, so the digits are read straight out rather than parsed into a zone
  # and shifted an hour off the schedule the reader is checking against. The
  # date is only ever read as a bare calendar date, which carries no zone to
  # shift.
  def blocker_slot_time(blocker, with_date: false)
    begins = blocker.dig("slot", "begins")
    return if begins.blank?
    return begins.strftime(with_date ? "%b %-d %H:%M" : "%H:%M") if begins.respond_to?(:strftime)

    text = begins.to_s
    time = text[/\d{1,2}:\d{2}/]
    return time unless with_date && time

    date = text[/\d{4}-\d{2}-\d{2}/]
    date ? "#{Date.parse(date).strftime("%b %-d")} #{time}" : time
  end
end
