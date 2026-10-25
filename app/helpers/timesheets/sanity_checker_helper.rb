# frozen_string_literal: true

# What each sanity check is called, and what it means.
#
# One table, read by the index rows, the detail page heading, the empty states
# and the export filename, so a check cannot be described one way on the board
# and another way on its own page. TimesheetSanityCheckReport holds the facts
# the arithmetic needs (band, grain); the words live here.
#
# Every method here is prefixed timesheet_check_ rather than sanity_check_.
# Rails mixes all helpers into one namespace for every view, and
# Bmid::SanityCheckHelper already owns sanity_check_meta -- the shorter names
# silently replaced its version and broke the BMID page instead of raising.
module Timesheets::SanityCheckerHelper
  # blurb: is the check page's hero description, so it is ONE sentence -- what
  # these rows are. Whatever else the reader needs goes in question: / answer:,
  # which the page folds into its About This Report card. A check with nothing
  # more to say (too_short) has neither; a test holds all three to that.
  CHECK_META = {
    on_duty: {
      label: "Still on duty",
      icon: "person-running",
      summary: "Entries with no sign-out",
      blurb: "These entries were never signed out.",
      question: "What should I do about these?",
      answer: "Ask the Ranger when the shift actually ended, then correct the entry.",
      empty: "Every entry has been signed out."
    },
    end_before_start: {
      label: "Off duty before on duty",
      icon: "arrow-right-arrow-left",
      summary: "Sign-out earlier than sign-in",
      blurb: "These entries end before they begin, which cannot have happened.",
      question: "How does this happen?",
      answer: "One of the two times was typed wrong.",
      empty: "No entry signs out before it signs in."
    },
    overlapping: {
      label: "Overlapping entries",
      icon: "layer-group",
      summary: "Two shifts running at once",
      blurb: "These Rangers were signed in to two positions at the same time.",
      question: "What should I do about these?",
      answer: "One entry needs its end time corrected, or removing.",
      empty: "No one was signed in to two positions at once."
    },
    too_long_for_shift: {
      label: "Longer than the scheduled shift",
      icon: "hourglass-end",
      summary: "Past 1.5 times the sign-up's length",
      blurb: "These entries ran to at least one and a half times the length of the " \
             "shift they were signed up for.",
      question: "Where is the scheduled shift?",
      answer: "The scheduled shift is shown under each entry.",
      empty: "No entry ran far past its scheduled shift."
    },
    too_short: {
      label: "Shift was too short",
      icon: "stopwatch",
      summary: "Fifteen minutes or less",
      blurb: "These entries lasted fifteen minutes or less, which usually means a " \
             "sign-in was undone rather than a shift rangered.",
      empty: "No entry lasted fifteen minutes or less."
    },
    too_long: {
      label: "Shift ran too long",
      icon: "clock",
      summary: "Past the position's recommended maximum",
      # No constant interpolated: this table is built while the helper module
      # itself is loading, and naming an autoloaded class there can deadlock
      # both autoloads. Kept in words, which the copy rules prefer anyway --
      # the Max Hours column shows each row's own number.
      blurb: "These entries ran to more than one and a half times the recommended " \
             "maximum for their position.",
      question: "What if a position has no recommended maximum?",
      answer: "A position with no recommendation of its own is flagged past a day and a half.",
      empty: "No entry ran far past its position's recommended maximum."
    },
    duplicate_alphas: {
      label: "Duplicate Alpha entries",
      icon: "user-group",
      summary: "More than one Alpha shift",
      blurb: "These Rangers have more than one Alpha entry.",
      question: "Why is that a problem?",
      answer: "A Ranger walks Alpha once, so one of them belongs to another position or to no one.",
      empty: "No one has more than one Alpha entry."
    },
    no_credits: {
      label: "No credits",
      icon: "circle-exclamation",
      summary: "Position credits may be misconfigured",
      blurb: "These entries earn nothing.",
      question: "What should I do about these?",
      answer: "That is usually a missing or mistimed credit range for the position rather than " \
              "anything the Ranger did — contact the Tech Team rather than editing the entries.",
      empty: "Every entry earns credits."
    }
  }.freeze

  # Who acts on a band, and how soon. The heading is the promise the grouping
  # makes, and it is an action; what: is the board's card answering what is
  # under it, so each line has to say so on its own.
  BAND_META = {
    contact: { title: "Contact Someone",
               what: "An open or impossible entry — somebody has to be asked what happened." },
    review: { title: "Review the Entry",
              what: "A duration that looks wrong, or a second Alpha entry. Decide it from the record." },
    configuration: { title: "Fix the Configuration",
                     what: "An entry that earns nothing because of how its position is configured — " \
                           "not a Ranger's mistake, and not fixable by editing timesheets." }
  }.freeze

  def timesheet_check_meta(key) = CHECK_META.fetch(key.to_sym)

  def timesheet_check_band_meta(band) = BAND_META.fetch(band.to_sym)

  def timesheet_check_path(key, year, **options)
    timesheets_sanity_checker_check_path(key.to_s.dasherize, year:, **options)
  end

  # What "Shift ran too long" measured this entry against. Positions
  # Position::PROBLEM_HOURS does not name fall back to the report's own
  # default rather than to the smallest listed value, which is what upstream
  # did by accident.
  def timesheet_check_max_hours(entry)
    Position::PROBLEM_HOURS.fetch(entry.position_id,
                                  TimesheetSanityCheckReport::DEFAULT_MAX_HOURS)
  end

  # How long an entry ran, for a page where that span can be anything.
  #
  # hour_minute_format alone is wrong at both ends here. It floors the hours
  # and takes a non-negative modulo, so a backwards entry of 1h02m renders as
  # "-2:58" -- and every row of "Off duty before on duty" is backwards. Above a
  # day it renders "336:00", which no reader can place, and the still-on-duty
  # and too-long pages are full of those.
  def timesheet_check_duration(seconds)
    seconds = seconds.to_i
    return hour_minute_or_day_format(seconds) unless seconds.negative?

    # Minus sign in front of a magnitude, rather than a negative clock: the
    # question on that page is how far apart the two times are.
    "-#{hour_minute_or_day_format(-seconds)}"
  end

  # "6 people" / "47 entries" -- the check's own grain, never a bare number.
  # An entry count and a people count sitting in the same column read as
  # comparable when they are not.
  def timesheet_check_count_label(key, count)
    pluralize(count, TimesheetSanityCheckReport.grain(key) == :people ? "person" : "entry")
  end

  # Findings are a problem, not an achievement, so a count that is not zero is
  # never styled as success.
  #
  # size: "base" when the badge goes into a drill-down row, which renders its
  # headline at text-lg -- ui_drill_down_row asks for it and every sibling
  # index passes it. The default stays xs for the standalone badge on the
  # detail page, where nothing sits beside it.
  def timesheet_check_badge(key, count, size: nil)
    ui_badge(timesheet_check_count_label(key, count),
             count.zero? ? :success : timesheet_check_variant(key),
             **(size ? { size: } : {}))
  end

  # The configuration band is not more urgent than the contact band, but it is
  # not a judgement call either: an entry earning nothing is definitely wrong,
  # where a long shift only might be.
  def timesheet_check_variant(key)
    TimesheetSanityCheckReport.band(key) == :review ? :warning : :error
  end
end
