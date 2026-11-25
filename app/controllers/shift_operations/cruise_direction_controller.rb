# frozen_string_literal: true

# Cruise Direction: the pods deployed on one dirt shift.
#
# The page opens on whichever shift is running right now, so an operator who
# lands here mid-event is already looking at the right board. Everything the
# page changes lives in the board partial and is streamed back by the two
# controllers next door.
#
# Upstream: Ember ops/cruise-direction.
class ShiftOperations::CruiseDirectionController < ShiftOperations::CruiseDirection::BaseController
  # A date as a link writes it: 2025-08-26, 2025-08-26 14:30 or 2025-08-26T14:30.
  # Year first and nothing else: Ruby reads 8/5/2025 as the 8th of May, and a
  # date opened three months off says nothing about why.
  #
  # Seconds and an offset may follow, as an ISO timestamp carries them, and are
  # ignored. A shift's times are the event's wall clock, so the digits are what
  # is compared; converting by the offset would move the answer a shift over.
  # The offset's sign is optional because an unescaped "+" arrives as a space.
  DATE_FORMAT = /\A(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?(?:\s*(?:Z|[+-]?\d{2}:?\d{2}))?)?\z/

  # For a link that knows when but not which shift. The role gate and
  # setup_year are registered above this class, so both have run before this.
  before_action :open_shift_on_date, if: -> { params[:date].present? }

  def index
    @shifts ||= CruiseDirectionBoard.shifts_for_year(@year)
    @slot = selected_slot
    @board = CruiseDirectionBoard.for_slot(@slot) if @slot
    @positions = CruiseDirectionBoard.positions
  end

  private

  # ?date= names a moment rather than a shift. The shift it lands in is sent
  # to the picker's own URL, so the page the reader ends up on reloads,
  # refreshes and bookmarks like a shift picked from the list.
  #
  # A date with a time lands in the shift covering it. A date alone means the
  # day, and opens the first shift that begins on it -- read as midnight it
  # would open the shift listed under the evening before.
  #
  # The date names its own year -- a link need not carry ?year= as well -- but
  # only a year this page shows. Any other would redirect to a year setup_year
  # then refuses, which is a page with no board and nothing said.
  def open_shift_on_date
    day, time = read_date(params[:date])
    shown = day&.year&.between?(year_floor, current_year)
    shift = (time ? CruiseDirectionBoard.shift_at(time) : CruiseDirectionBoard.first_shift_on(day)) if shown
    return redirect_to shift_operations_cruise_direction_path(slot_id: shift.id, year: day.year) if shift

    # The picker follows the date to its year, so "the list" in the message is
    # the one the reader was after. Both of setup_year's answers move together.
    @year, @is_current_year = day.year, day.year == current_year if shown
    @shifts = CruiseDirectionBoard.shifts_for_year(@year)
    flash.now[:error] = date_not_found(day, time)
  end

  # The day and, when one was given, the moment. nil for anything else: a day
  # no calendar has, an hour no clock has, or a value that is not text
  # (?date[]=x is an Array).
  def read_date(raw)
    match = DATE_FORMAT.match(raw) if raw.is_a?(String)
    return unless match

    year, month, mday, hour, minute = match.captures.map { |part| part&.to_i }
    return unless Date.valid_date?(year, month, mday)

    day = Date.new(year, month, mday)
    return [day, nil] unless hour

    [day, Time.zone.local(year, month, mday, hour, minute)] if hour < 24 && minute < 60
  end

  # The constants rather than datetime_format, which answers with a <span> for
  # a view and would print as markup inside a toast. A year with no dirt
  # shifts has no list to send the reader to.
  def date_not_found(day, time)
    stamp = if time
              time.strftime(DateTimeHelper::MONTH_DAY_TIME_YEAR)
            elsif day
              day.strftime("#{DateTimeHelper::DAY_LABEL}, %Y")
            else
              "that date"
            end

    ["No dirt shift was found for #{stamp}.", ("Pick a shift from the list." if @shifts.any?)].compact.join(" ")
  end

  # The shift picked from the list, or -- on the first view -- the one running
  # right now. Resolved against the year's dirt shifts, so a slot id left over
  # from another year or another kind of shift cannot select anything.
  #
  # A date that found no shift selects nothing, whatever else the link says:
  # any board under that error would read as the date's.
  #
  # A String only: ?slot_id[]=1 is an Array, which is not blank and does not
  # answer to_i.
  def selected_slot
    return if params[:date].present?

    slot_id = params[:slot_id]
    shift =
      if slot_id.blank?
        CruiseDirectionBoard.suggested_shift(@shifts)
      elsif slot_id.is_a?(String)
        @shifts.find { |dirt_shift| dirt_shift.id == slot_id.to_i }
      end

    Slot.find_by(id: shift.id) if shift
  end
end
