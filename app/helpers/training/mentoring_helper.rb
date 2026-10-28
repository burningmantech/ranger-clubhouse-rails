# frozen_string_literal: true

# Presentation for an ART's mentoring pages: how a mentoring shift is named,
# the window of sign-ins it lists, the mentor select's options, and the two
# reports' filters and shift chips.
module Training::MentoringHelper
  # The button on a recorded pass that still has something to grant; the
  # roster's card names it too.
  GRANT_TEAM_POSITIONS = "Grant Team Positions"
  # The pass question's other answers (owner, 2026-10-28): each is a submit
  # named `confirmed` whose value is its label, read back by the controller.
  RECORD_PASS_NOT_PROMOTE = "Record Pass but Not Promote"
  PROMOTE_WITHOUT_VERDICT = "Promote Without a Verdict"
  # The picker's badge on sign-ins that matched no shift; its card explains it.
  CHECK_SIGN_IN = "Check the sign-in"
  # Where a walk's mentee entry was deleted (ruled 2026-10-21); the Verdicts
  # card explains it.
  SHIFT_DELETED = "Shift deleted"

  VERDICT_FILTER_LABELS = { status: "Verdict", mentor_id: "Mentor" }.freeze
  MULTIPLE_SHIFTS_FILTER_LABELS = { kind: "Kind", callsign: "Callsign" }.freeze
  MULTIPLE_SHIFTS_KINDS = {
    ArtMentoring::MultipleShiftsReport::RANGERED => "Rangered two or more",
    ArtMentoring::MultipleShiftsReport::SIGNED_UP => "Signed up again"
  }.freeze

  # When a walk's shift started, or -- its entry deleted -- that, muted. The
  # Verdicts page and the Me/Person mentoring pages print it alike; `short`
  # is the card form ("Wed 9/2 18:00"), which fits a mentoring card's width.
  def art_walk_shift_label(on_duty, short: false)
    return short ? short_datetime_format(on_duty) : datetime_format(on_duty) if on_duty

    tag.span SHIFT_DELETED, class: "text-stone-muted"
  end

  # A shift's title: its time, or -- for sign-ins that matched no shift -- that.
  def art_mentoring_shift_label(group)
    return "No Matching Shift" if group.unmatched?

    datetime_format(group.begins, group.ends, tz: group.slot.timezone)
  end

  # The clock times a group's window covers (Shifts::Group#window), so the page
  # can state them rather than ask the reader to do the arithmetic. Dated, not
  # bare times: a late-night window crosses midnight. safe_join, because
  # datetime_format returns markup that interpolation would escape into view.
  # The window is built from the shift's start, in the shift's own zone, or for
  # an unmatched group from a sign-in, which is on the app's clock.
  def art_mentoring_window(group)
    tz = group.slot&.timezone
    safe_join([datetime_format(group.window.begin, tz:), datetime_format(group.window.end, tz:)], " and ")
  end

  # The two counts the mentoring pages share, as their stat tiles: mentees on
  # shift no one is paired with, and mentees signed out with no verdict yet.
  def art_need_mentor_box(count)
    ui_stat_box count.to_s, "Need a Mentor", variant: count.positive? ? :warning : :success,
                                             icon: "user-clock", icon_type: :solid
  end

  def art_awaiting_verdict_box(count)
    ui_stat_box count.to_s, "Awaiting a Verdict", variant: count.positive? ? :warning : :success,
                                                  icon: "hourglass-half", icon_type: :solid
  end

  # A picker card's mentees, each once by callsign, with their sign-ins when
  # there are more than one ("Tinsel (2 sign-ins)"): the card's badge and meter
  # count sign-ins.
  def art_mentee_names(group)
    group.mentee_entries.group_by(&:person_id).values.map do |entries|
      name = person_display_name(entries.first.person, entries.first.person_id)
      entries.one? ? name : "#{name} (#{pluralize(entries.size, "sign-in")})"
    end.sort_by(&:downcase).to_sentence
  end

  # A walk's notes, one line for each mentor who wrote some ("Ferrous: Ready."),
  # or a dash: each mentor keeps their own (ruled 2026-10-27).
  def art_walk_notes(walk)
    noted = (walk&.rows || []).select { |row| row.notes.present? }
    return value_or_dash(nil) if noted.empty?

    safe_join(noted.map do |row|
      tag.div("#{person_display_name(row.mentor, row.mentor_id)}: #{row.notes}", class: "whitespace-pre-line")
    end)
  end

  # How long an entry has run: "1:36 so far" while it is open.
  def art_mentoring_duration(entry)
    length = hour_minute_format(entry.duration)
    entry.off_duty ? length : "#{length} so far"
  end

  # One of a mentee entry's mentor selects (ruled 2026-10-21): the mentors
  # signed in around the shift, then everyone else holding the mentor position,
  # then a mentor recorded on this walk who no longer holds it. Without that
  # last group the select would blank a real record and the next save would
  # delete it. The mentee is never offered as their own mentor: the save
  # refuses it.
  def art_mentor_choices(group, holders, entry, selected)
    walk = group.walk_for(entry)
    on_shift = group.mentor_entries.filter_map do |mentor|
      next if mentor.person_id == entry.person_id

      ["#{mentor.person.callsign} · signed in #{mentor.on_duty.strftime(DateTimeHelper::HOUR_MINS)}", mentor.person_id]
    end.uniq(&:last)
    listed = on_shift.to_set(&:last) << entry.person_id
    others = holders.reject { |person| listed.include?(person.id) }.map { |person| [person.callsign, person.id] }
    listed.merge(others.map(&:last))
    former = (walk&.rows || []).reject { |row| row.mentor_id.nil? || listed.include?(row.mentor_id) }
                               .map { |row| [person_display_name(row.mentor, row.mentor_id), row.mentor_id] }

    mentor_choices([["On shift", on_shift], ["Other mentors", others], ["No longer a mentor", former]], selected)
  end

  # ------------------------------------------------------------ the reports

  # Every result but Pending: a pending walk has no verdict to filter by.
  def art_verdict_options
    filter_select_options(MentorHelper::RESULT_LABELS.slice(*ArtMentoring::VerdictsReport::VERDICTS))
  end

  # The mentors the verdicts name, { id => name }: one map for the Mentor
  # filter's options and its chip, so the two read alike. A pass recorded
  # without a mentor names none.
  def art_verdict_mentor_names(verdicts)
    verdicts.select(&:mentor_id).to_h { |walk| [walk.mentor_id.to_s, person_display_name(walk.mentor, walk.mentor_id)] }
  end

  # The mentors the verdicts name, by callsign.
  def art_verdict_mentor_options(verdicts)
    filter_select_options(art_verdict_mentor_names(verdicts).sort_by { |_id, name| name.downcase })
  end

  def art_verdict_filter_chips(filter_params, slug, year, verdicts)
    names = art_verdict_mentor_names(verdicts)
    label = ->(key, value) { key == :status ? mentor_result_label(value) : names.fetch(value, value) }
    filter_chips(active_filters(filter_params), VERDICT_FILTER_LABELS, value_label: label) do |remaining|
      training_mentoring_verdicts_path(slug, **remaining, year:)
    end
  end

  def art_multiple_shifts_filter_chips(filter_params, slug, year)
    label = ->(key, value) { key == :kind ? MULTIPLE_SHIFTS_KINDS.fetch(value, value) : value }
    filter_chips(active_filters(filter_params), MULTIPLE_SHIFTS_FILTER_LABELS, value_label: label) do |remaining|
      training_mentoring_multiple_shifts_path(slug, **remaining, year:)
    end
  end

  # A mentee's shifts as chips: each one rangered, on now, or signed up for.
  def art_mentee_shift_chips(row)
    rangered = row.entries.map do |entry|
      if row.on_shift.include?(entry)
        ui_badge "#{short_datetime_format(entry.on_duty)} · on shift", :success, icon: "person-walking",
                                                                                icon_type: :solid
      else
        ui_badge short_datetime_format(entry.on_duty), :secondary, icon: "calendar-check", icon_type: :solid
      end
    end
    signed_up = row.signups.map do |slot|
      ui_badge "#{short_datetime_format(slot.begins)} · signed up", :info, icon: "calendar", icon_type: :solid
    end
    tag.div(safe_join(rangered + signed_up), class: "flex flex-wrap gap-1")
  end
end
