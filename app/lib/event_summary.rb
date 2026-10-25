# frozen_string_literal: true

# WorkSummary
#
# Computes the pre-event, event, and post-event credits and durations
# for a given set of timesheet entries.
class EventSummary
  attr_accessor :event_start, :event_end, :year,
                :pre_event_credits, :event_credits, :post_event_credits,
                :pre_event_duration, :event_duration, :post_event_duration,
                :other_duration, :excluded_timesheets

  # year_credits: the year's credit rates keyed by position, for a caller
  # summarizing many people at once. Reading them per shift means rebuilding the
  # whole year's rates thousands of times over, which turns a season's worth of
  # shifts into minutes of counting. Left out, one summary reads them itself.
  def initialize(event_start, event_end, year, year_credits: nil)
    @event_start = event_start
    @event_end = event_end
    @year = year
    @year_credits = year_credits || PositionCredit.year_credits(year)

    @pre_event_credits = 0
    @event_credits = 0
    @post_event_credits = 0

    @pre_event_duration = 0
    @event_duration = 0
    @post_event_duration = 0

    @other_duration = 0

    @excluded_timesheets = []
  end

  # Compute the credits and durations for a timesheet entry based on when
  # the shift occurred relative to the event period.
  #
  # @param position_id [Integer] The position ID
  # @param on_duty [Time] When the shift started
  # @param off_duty [Time] When the shift ended
  # @param count_hours [Boolean] Whether to count hours toward duration totals
  # @return [void]
  def compute_totals(position_id, on_duty, off_duty, count_hours)
    # The following bits were adopted from the old Hours and Credits report written by Socrates back in 2014.

    unless count_hours
      # Dump time into other category if hours are not to be counted.
      @other_duration += (off_duty - on_duty)
    end

    if on_duty < @event_start
      # On duty before event
      compute_on_duty_before_event(position_id, on_duty, off_duty, count_hours)
    elsif on_duty <= @event_end
      # On duty during event
      compute_on_duty_during_event(position_id, on_duty, off_duty, count_hours)
    else
      # On duty after event
      compute_on_duty_after_event(position_id, on_duty, off_duty, count_hours)
    end
  end

  private

  # What one stretch of a shift earned, against the rates read once up front.
  def credits_for(position_id, start_time, end_time)
    PositionCredit.credits_for(@year_credits[position_id], start_time, end_time)
  end

  # Handle case when shift started before the event
  def compute_on_duty_before_event(position_id, on_duty, off_duty, count_hours)
    if off_duty < @event_start
      # On-duty before & off-duty before event
      @pre_event_credits += credits_for(position_id, on_duty, off_duty)
      @pre_event_duration += (off_duty - on_duty) if count_hours
    elsif off_duty <= @event_end
      # On-duty before event and off-duty during event
      @pre_event_credits += credits_for(position_id, on_duty, @event_start)
      @event_credits += credits_for(position_id, @event_start, off_duty)

      if count_hours
        @pre_event_duration += (@event_start - on_duty)
        @event_duration += (off_duty - @event_start)
      end
    else
      # On duty before event and off duty after event (aka: needs a life)
      @pre_event_credits += credits_for(position_id, on_duty, @event_start)
      @event_credits += credits_for(position_id, @event_start, @event_end)
      @post_event_credits += credits_for(position_id, @event_end, off_duty)

      if count_hours
        @pre_event_duration += (@event_start - on_duty)
        @event_duration += (@event_end - @event_start)
        @post_event_duration += (off_duty - @event_end)
      end
    end
  end

  # Handle case when shift started during the event
  def compute_on_duty_during_event(position_id, on_duty, off_duty, count_hours)
    if off_duty <= @event_end
      @event_credits += credits_for(position_id, on_duty, off_duty)
      @event_duration += (off_duty - on_duty) if count_hours
    else
      @event_credits += credits_for(position_id, on_duty, @event_end)
      @post_event_credits += credits_for(position_id, @event_end, off_duty)

      if count_hours
        @event_duration += (@event_end - on_duty)
        @post_event_duration += (off_duty - @event_end)
      end
    end
  end

  # Handle case when shift started after the event
  def compute_on_duty_after_event(position_id, on_duty, off_duty, count_hours)
    @post_event_credits += credits_for(position_id, on_duty, off_duty)
    @post_event_duration += (off_duty - on_duty) if count_hours
  end
end
