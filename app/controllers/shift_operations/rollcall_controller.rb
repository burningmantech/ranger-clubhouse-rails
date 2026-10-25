# frozen_string_literal: true

# Tap-a-name rollcall for burn-night crews (Ember ops/rollcall port).
#
# Two rosters behind a mode chooser. Sign In lists the sign-ups for one shift
# in the rollcall window; Sign Out lists everyone still out. On both, tapping a
# Ranger writes immediately — there is no review step and no submit button,
# because the operator is standing at a staging area in the dark with a queue
# of people in front of them.
#
# Every write answers with a turbo stream that replaces the one row that
# changed plus the header count, and nothing else. A redirect would be wrong
# here rather than merely slower: it would throw an operator who is partway
# down a hundred-and-fifty-name roster back to the top of it.
#
# Rollcall never forces a blocked check-in, even for an operator who holds the
# privilege. Upstream does not send force_sign_in from this page either — a
# blocker here means the Ranger has something to resolve, and the page says to
# send them to an HQ window, which is where the forcing UI lives.
class ShiftOperations::RollcallController < ApplicationController
  layout "shift_operations"

  # Upstream gates the menu item on admin or shift-management, and the API
  # policy behind every write on this page (signin, signoff, resignin) checks
  # Shift Management. Shift Management Self is deliberately absent: it grants
  # a person power over their own shifts, and nothing on this page is about
  # the operator's own shift.
  authorize_role [Role::ADMIN, Role::SHIFT_MANAGEMENT],
                 message: "Shift Management role required to run roll call."

  # The mode chooser. Nothing is loaded until a mode is picked — this page is
  # opened on playa bandwidth and neither roster is cheap.
  def index
  end

  # @group is a Rollcall::Group in both actions, not a Position — it answers
  # #id and #title, so a name suggesting otherwise never gets corrected.
  def sign_in
    @groups = Rollcall.shift_groups
    @group = find_group(params[:position_id])
    @slot = find_slot(@group)
    @rows = @slot ? Rollcall.sign_in_roster(@slot) : []
    @counts = @slot && Rollcall.sign_in_counts(@slot.id, @slot.position_id)
    @start_time = start_time_param
  end

  def sign_out
    @groups = Rollcall.sign_out_positions
    @group = find_group(params[:position_id])
    @rows = @group ? Rollcall.sign_out_roster(@group.id) : []
    @counts = @group && { on_duty: Rollcall.on_duty_count(@group.id) }
  end

  # Sign one Ranger into the selected shift.
  def check_in
    person = find_person
    return unless person

    result = ShiftManage.sign_in(person: person, position_id: params[:position_id],
                                 slot_id: signed_in_slot_id,
                                 start_time: start_time_param, user: current_user)

    # entry: is always passed, never looked up again. ShiftManage has just
    # saved or found the very row the reply needs; and where it carries none,
    # nil is the answer -- sign_in returns :already_on_duty before any other
    # refusal, so a :blocked or :position_not_held result proves the Ranger is
    # not out.
    case result.status
    when :success
      respond_with_row person, entry: result.entry, notice: check_in_notice(person, result)
    when :blocked
      respond_with_row person, entry: nil, dialog: blocked_locals(person, result)
    when :already_on_duty
      respond_with_row person, entry: result.entry,
                       alert: "#{person.callsign} is already on duty. The row now shows where."
    when :position_not_held
      respond_with_row person, entry: nil,
                       alert: "#{person.callsign} does not hold this position and cannot be " \
                              "signed in. Send them to an HQ window."
    else
      respond_with_row person, entry: nil, alert: failure_message(person, result.status)
    end
  end

  # Sign one Ranger off. Used by both rosters.
  def check_out
    person = find_person
    return unless person

    entry = Timesheet.find_person_on_duty(person.id)
    unless entry
      return respond_with_row(person, entry: nil, alert: "#{person.callsign} is not on duty.")
    end

    # The row asserted which entry was open. If that is no longer the one, the
    # board is stale -- the Ranger was signed off and back on somewhere else
    # since this row was drawn -- and ending "whatever is open" would close a
    # shift the operator never saw. Redraw instead and let them look.
    asserted = params[:entry_id].presence
    if asserted && asserted.to_i != entry.id
      return respond_with_row(person, entry: entry,
                              alert: "#{person.callsign}'s shift changed since this roster was " \
                                     "drawn. The row now shows the current one.")
    end

    result = ShiftManage.sign_off(entry, user: current_user)
    if result.status == :success
      respond_with_row person, entry: entry, notice: check_out_notice(person, result)
    else
      respond_with_row person, entry: entry,
                       alert: "#{person.callsign} was already signed off."
    end
  end

  # Resume a shift ended by mistake — the second tap on a row this page just
  # signed off. Scoped to the person so a hand-posted entry_id cannot reopen
  # somebody else's shift.
  def resume
    person = find_person
    return unless person

    # Bounded to a shift that ended within the resignin window, not just to
    # this person. An unbounded find_by lets a hand-posted entry_id reopen a
    # shift closed years ago, and clearing off_duty on it records an open
    # entry tens of thousands of hours long — invisible here and on the On
    # Duty board, since both are year-scoped, and surfacing only in Mass
    # Signout. This page's undo only ever means "the tap I just made".
    entry = ShiftManage.recently_signed_off_entry(person)
    if entry.nil? || entry.id != params[:entry_id].to_i
      return respond_with_row(person, entry: nil,
                              alert: "That shift is no longer available to resume.")
    end

    result = ShiftManage.resignin(entry)
    case result.status
    when :success
      respond_with_row person, entry: entry,
                               notice: "#{person.callsign} is back on shift with " \
                                       "#{entry.position&.title}."
    when :already_on_duty
      # resignin hands back the entry that blocked it -- the row should show
      # the shift they are actually on, not the one that failed to reopen.
      respond_with_row person, entry: result.entry,
                               alert: "#{person.callsign} is already on duty."
    else
      respond_with_row person, entry: entry, alert: failure_message(person, result.status)
    end
  end

  private

  # --- Responses -----------------------------------------------------------

  # The whole response contract of this page: the tapped row, the count beside
  # the roster title, a toast, and optionally a dialog. Streams only — an
  # HTML-format request for one of these POSTs has no meaning, and answering
  # it with a redirect would be the full page reload this page exists to avoid.
  #
  # The row is rebuilt from committed state rather than from what the tap
  # assumed, so a refused write leaves the row telling the truth.
  def respond_with_row(person, entry:, notice: nil, alert: nil, dialog: nil)
    row = Rollcall.row_for(person, entry)
    streams = [turbo_stream.replace(helpers.rollcall_row_id(person.id),
                                    partial: "shift_operations/rollcall/row",
                                    locals: row_locals(row))]
    streams << count_stream
    if dialog
      streams << turbo_stream.update("modal",
                                     partial: "shift_operations/rollcall/blocked_dialog",
                                     locals: dialog)
    end
    streams << ui_toast_stream(notice, :success) if notice
    streams << ui_toast_stream(alert, :error) if alert

    render turbo_stream: streams.compact
  end

  # The "57 of 142 signed in" line, recounted after every tap.
  #
  # Counted in the database, not by rebuilding the roster the tap came from:
  # the numbers are the only thing wanted, and rebuilding a 178-person roster
  # to derive them costs eight queries and six hundred objects per tap.
  #
  # replace, not update: the partial carries the target's own id, so an update
  # -- which swaps inner HTML -- would nest the count element inside itself and
  # leave two elements with id="rollcall-count" on the page. The layout morphs
  # on refresh and reconciles by id, so duplicates there can silently drop
  # content.
  def count_stream
    counts = roster_counts
    return nil unless counts

    turbo_stream.replace("rollcall-count",
                         partial: "shift_operations/rollcall/count",
                         locals: { counts: counts, mode: roster_mode })
  end

  # Sign-out answers a zero count rather than nil for a position no one is left
  # on: that is what the count has to say once the last Ranger goes off duty,
  # and a nil here would drop the stream and leave the previous number frozen
  # on screen.
  # Straight from the params the row posted -- both ids are already there, and
  # the write on the way in trusted the same position_id.
  def roster_counts
    if roster_mode == :sign_out
      { on_duty: Rollcall.on_duty_count(params[:position_id]) }
    else
      return nil if params[:slot_id].blank? || params[:position_id].blank?

      Rollcall.sign_in_counts(params[:slot_id], params[:position_id])
    end
  end

  def roster_mode = Rollcall.mode_from(params[:mode])

  # Locals every render of a row needs, in both modes.
  def row_locals(row)
    { row: row, mode: roster_mode, position_id: params[:position_id],
      slot_id: params[:slot_id].presence, start_time: start_time_param }
  end

  def blocked_locals(person, result)
    { callsign: person.callsign, blockers: result.blockers, start_time: start_time_param }
  end

  # --- Messages ------------------------------------------------------------

  def check_in_notice(person, result)
    message = +"#{person.callsign} is on shift."
    on_duty = result.entry&.on_duty
    message << " Check-in time set to #{helpers.rollcall_clock(on_duty)}." if start_time_param && on_duty
    message
  end

  def check_out_notice(person, result)
    message = +"#{person.callsign} has been signed off."
    if result.now_active
      message << " Their account status was automatically converted back to Active."
    end
    message
  end

  def failure_message(person, status)
    case status
    when :position_not_eligible
      "That position does not take timesheet entries."
    when :invalid_start_time, :start_time_out_of_range
      "The check-in time must be a real time within the last several hours. Clear it and try again."
    when :start_time_overlaps
      "The check-in time falls inside a shift #{person.callsign} has already finished. " \
        "Clear it or set a later one."
    when :not_signed_off
      "#{person.callsign} is still on shift — there is nothing to resume."
    else
      "The action failed with an unexpected status [#{status}]. " \
        "This is a bug — please report it to the Tech Ninjas."
    end
  end

  # --- Lookups -------------------------------------------------------------

  # A tap names a person by id. An id that is not on the roster is not
  # rejected specially — every write below re-checks live state anyway, and
  # the row that comes back is drawn from that state.
  def find_person
    person = Person.find_by(id: params[:person_id])
    return person if person

    render turbo_stream: helpers.ui_toast_stream("That Ranger could not be found.", :error)
    nil
  end

  def find_group(position_id)
    return nil if position_id.blank?

    @groups.find { |group| group.id == position_id.to_i }
  end

  # The shift being signed into. A position offering exactly one shift selects
  # it without being asked — upstream does this, and it removes a tap from the
  # common case where a position has one shift running.
  def find_slot(group)
    return nil unless group
    return group.members.first if group.members.one?

    group.members.find { |slot| slot.id == params[:slot_id].to_i }
  end

  # A blank override is no override. Kept as nil rather than "" so
  # ShiftManage.sign_in sees the same absence a page without the dialog does.
  #
  # Shape-checked here, not only at the write: the page states the set time
  # back to the operator as fact ("every sign-in below is recorded at ...")
  # and stamps it into all hundred and fifty rows. A malformed one would make
  # that banner a lie and every tap a silent failure, so an unusable value is
  # dropped at the door and the page renders as though none was set.
  def start_time_param
    value = params[:start_time].presence
    value if value&.match?(ShiftManage::START_TIME_FORMAT)
  end

  # The shift a check-in is recorded against, and only if it really is a shift
  # on the position being signed into. The rendered pickers always agree, so
  # this only bites a hand-posted request -- but the pair is written straight
  # onto the timesheet, where a mismatched slot_id would misreport the shift
  # in every downstream no-show and check-in-timing report.
  def signed_in_slot_id
    slot_id = params[:slot_id].presence
    return nil unless slot_id
    return nil unless Slot.exists?(id: slot_id, position_id: params[:position_id])

    slot_id
  end
end
