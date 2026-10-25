# frozen_string_literal: true

# Row painting for the roll call board.
#
# Never colour alone: every state also carries its own icon and says what it is
# in words, because this page is used outdoors at night by operators who may be
# colour-blind, and a green row and a red row must not be told apart by hue.
#
# Helper names are one global namespace in Rails, so everything here is
# rollcall_-prefixed.
module ShiftOperations::RollcallHelper
  # What a row looks like and what tapping it does. Keyed by the state
  # rollcall_row_state derives; :label is the badge, :detail the second line.
  #
  # The neutral surface is bg-default, not bg-base-100: <main> is base-100 in
  # BOTH themes, so a base-100 row has no surface of its own on either and
  # reads only by its border. base-200 lifts off the page in dark and settles
  # into it in light, which is the card relationship the rest of the app has.
  STATES = {
    # Sign In roster.
    off: { badge: "Tap to sign in", variant: :secondary, icon: "hand-pointer",
           row: "bg-default border-base-300" },
    # confirm: tapping one of these on the SIGN IN roster ends a shift, which
    # is the opposite of what the operator came to that page to do.
    signed_in: { badge: "On duty", variant: :success, icon: "person-walking",
                 row: "bg-success/10 border-success", confirm: true },
    elsewhere: { badge: "On duty elsewhere", variant: :error, icon: "triangle-exclamation",
                 row: "bg-error/10 border-error", confirm: true },
    # Sign Out roster.
    out: { badge: "Tap to sign out", variant: :secondary, icon: "person-walking",
           row: "bg-default border-base-300" },
    signed_off: { badge: "Signed off", variant: :success, icon: "bed",
                  row: "bg-success/10 border-success" },
    # Nothing to sign off and nothing to resume -- somebody else got there
    # first. Inert on purpose: it carries no action, so the row renders
    # without a button rather than as a tap that can only be refused.
    gone: { badge: "No longer on duty", variant: :secondary, icon: "circle-minus",
            row: "bg-default border-base-300", inert: true }
  }.freeze

  # The DOM id a turbo stream replaces. One per person per page, which is what
  # keeps a roster of a hundred and fifty rows free of duplicate ids.
  def rollcall_row_id(person_id) = "rollcall-person-#{person_id}"

  # Which of STATES this row is in. The sign-in roster distinguishes a Ranger
  # out on THIS shift's position from one out on another; upstream could not,
  # because it tracked "signed in" as browser state that a reload threw away,
  # so a Ranger signed in a minute ago came back red as though they were
  # somewhere else. Reading it off the entry instead makes the row say the
  # same thing however it was rendered -- which it has to, since every tap
  # re-renders it from the database.
  def rollcall_row_state(row, mode, position_id)
    if mode == :sign_out
      # A sign-out row with no entry at all has nothing to sign off and
      # nothing to resume -- it is somebody another operator (or an HQ window)
      # already dealt with. Painting that :signed_off would dress a tap that
      # wrote nothing in the green success state and offer a resume whose
      # entry_id is nil, which the controller can only refuse forever.
      return :gone if row.entry.nil?

      row.on_duty? ? :out : :signed_off
    elsif !row.on_duty?
      :off
    else
      row.elsewhere?(position_id) ? :elsewhere : :signed_in
    end
  end

  # The POST a tap sends. Sign-out rows that were just signed off offer to
  # resume the entry they ended; everything else signs in or signs off.
  def rollcall_row_action(state)
    case state
    when :off then :check_in
    when :signed_off then :resume
    else :check_out
    end
  end

  # Positions for the picker, in two optgroups. Burn positions come first
  # because on the night this page is used they are what it is used for; the
  # groups are dropped when empty rather than rendered as bare headings.
  def rollcall_position_option_groups(groups)
    burn, rest = groups.partition(&:burn?)
    [["Burn Positions", burn.map { |g| [g.title, g.id] }],
     ["Everything Else", rest.map { |g| [g.title, g.id] }]].reject { |_, options| options.empty? }
  end

  def rollcall_slot_options(group)
    return [] unless group

    group.members.map { |slot| [rollcall_slot_label(slot), slot.id] }
  end

  def rollcall_row_path(action)
    case action
    when :check_in then shift_operations_rollcall_check_in_path
    when :resume then shift_operations_rollcall_resume_path
    else shift_operations_rollcall_check_out_path
    end
  end

  # Everything the POST needs to write, and to redraw the roster count and the
  # row it answers with.
  #
  # start_time rides on EVERY action, not just the check-in that consumes it:
  # the reply re-renders the row from this request's own params, so a check-out
  # that dropped it would hand back a row with no set time in it, and the next
  # tap on that row would sign the Ranger in at the wall clock while the banner
  # overhead still promised the set time.
  #
  # entry_id likewise rides on both writes that touch an existing entry. It is
  # what the row asserted was open; the controller refuses if that is no longer
  # what is open, rather than signing off whatever it finds.
  #
  # Named fields, not params: `params` is a real method in a helper, and a
  # local by that name shadows it for the whole body.
  def rollcall_row_params(row, action, mode:, position_id:, slot_id:, start_time:)
    fields = { person_id: row.person_id, mode: mode, position_id: position_id,
               slot_id: slot_id, start_time: start_time }
    fields[:entry_id] = row.entry&.id if action != :check_in
    fields.compact
  end

  # Signing a Ranger out from the SIGN IN roster is confirmed: the operator
  # went there to sign people in, and the tap that ends someone's shift is the
  # same gesture as the tap that starts it. The sign-out roster asks nothing --
  # ending shifts is the entire reason the operator opened it.
  #
  # Keyed off the state, not off mode + action: the state already encodes both,
  # and reading it here was the one place mode leaked past the point where it
  # had been collapsed.
  def rollcall_row_confirm(row, state)
    return {} unless STATES.dig(state, :confirm)

    { turbo_confirm: confirm_modal_dialog(
      title: "Sign Out #{row.callsign}",
      message: "Sign out #{row.callsign}? #{row.callsign} is on duty. Signing them out records them as going off duty " \
               "right now.",
      confirm_label: "Sign Them Out"
    ) }
  end

  # The second line: which position, since when, and how long. Kept to
  # metadata -- a position and a time -- which is what text-sm is for and what
  # a dense roster can afford. The badge and the accessible label carry the
  # meaning; an explanatory sentence here would be neither.
  def rollcall_row_detail(row, state)
    entry = row.entry
    return nil if entry.nil?

    case state
    when :signed_in, :out, :elsewhere
      "#{value_or_dash(entry.position&.title)} · since #{rollcall_clock(entry.on_duty)}"
    when :signed_off
      "#{value_or_dash(entry.position&.title)} · #{hour_minute_format(entry.duration)} on duty"
    end
  end

  # A wall clock for tonight: bare HH:MM for today, with the weekday once the
  # time is not today's. datetime_format is the wrong tool here -- it returns a
  # tooltip <span> and prints the date every time, which is noise on a row
  # whose whole point is to be read at a glance in the dark.
  def rollcall_clock(time)
    return "" if time.blank?

    format = (time.to_date == Current.time.to_date) ? DateTimeHelper::HOUR_MINS
                                                    : DateTimeHelper::HOUR_MIN_DAY
    time.strftime(format)
  end

  # "Sat Aug 30 @ 20:45 (Burn Night)" -- how a shift reads in the picker.
  def rollcall_slot_label(slot)
    "#{slot.begins.strftime(DateTimeHelper::MONTH_DAY_TIME)} (#{slot.description})"
  end

  # The roster headline count -- the number each operator is driving to a
  # target, and the second thing every tap replaces. Takes counts, not rows:
  # they come from COUNT queries rather than from rebuilding the roster.
  #
  # Sign In has a stable denominator (the shift's sign-ups) and uses it. Sign
  # Out has none: its roster is everyone out right now, so a Ranger who signs
  # off leaves the set the server can recount, and the last one to go would
  # take the whole count element with them. It reports the live number alone.
  def rollcall_count_label(counts, mode)
    if mode == :sign_out
      "#{pluralize(counts[:on_duty], "Ranger")} still on duty"
    else
      "#{counts[:signed_in]} of #{counts[:total]} signed in"
    end
  end

  # The accessible name for the row button. The badge and the tint say the
  # state to anyone who can see them; this is what says it to anyone who
  # cannot, and it has to name the action, not just the state.
  # Every state spells its own label. Deriving it from the badge instead read
  # "Sign out Fuzzy, currently tap to sign out" on every row of the Sign Out
  # roster, because that badge is a call to action rather than a state -- the
  # kind of thing only a reader who cannot see the row ever hears.
  def rollcall_row_aria_label(row, state)
    case state
    when :off then "Sign in #{row.callsign}"
    when :out then "Sign out #{row.callsign}"
    when :signed_off then "Resume #{row.callsign}'s shift"
    when :gone then "#{row.callsign} is no longer on duty"
    when :elsewhere then "Sign out #{row.callsign}, who is on duty on another position"
    else "Sign out #{row.callsign}, who is on duty"
    end
  end
end
