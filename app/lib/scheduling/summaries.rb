# frozen_string_literal: true

module Scheduling::Summaries
  # Result class for schedule summary
  class ScheduleSummary
    attr_accessor :pre_event_duration,
                  :pre_event_credits,
                  :event_duration,
                  :event_credits,
                  :post_event_duration,
                  :post_event_credits,
                  :total_duration,
                  :total_credits,
                  :other_duration,
                  :counted_duration,
                  :event_start,
                  :event_end,
                  :credits_earned

    def initialize(pre_event_duration: 0, pre_event_credits: 0,
                   event_duration: 0, event_credits: 0,
                   post_event_duration: 0, post_event_credits: 0,
                   total_duration: 0, total_credits: 0,
                   other_duration: 0, counted_duration: 0,
                   event_start: nil, event_end: nil, credits_earned: 0.0)
      @pre_event_duration = pre_event_duration
      @pre_event_credits = pre_event_credits
      @event_duration = event_duration
      @event_credits = event_credits
      @post_event_duration = post_event_duration
      @post_event_credits = post_event_credits
      @total_duration = total_duration
      @total_credits = total_credits
      @other_duration = other_duration
      @counted_duration = counted_duration
      @event_start = event_start
      @event_end = event_end
      @credits_earned = credits_earned
    end
  end

  # Shift info for starting slots
  class ShiftInfo
    attr_accessor :slot_id, :slot_description,
                  :position_id, :position_title, :slot_begins,
                  :slot_ends, :slot_timezone, :slot_info, :is_within_start_time, :can_start_in

    def initialize(slot_id:, slot_description:, position_id:, position_title:,
                   slot_begins:, slot_ends:, slot_timezone:, slot_info: nil,
                   is_within_start_time: true, can_start_in: nil)
      @slot_id = slot_id
      @slot_description = slot_description
      @position_id = position_id
      @position_title = position_title
      @slot_begins = slot_begins
      @slot_ends = slot_ends
      @slot_timezone = slot_timezone
      @slot_info = slot_info
      @is_within_start_time = is_within_start_time
      @can_start_in = can_start_in
    end
  end

  # Result class for shift signups summary
  class ShiftSignupsSummary
    attr_accessor :total_duration, :counted_duration, :credits, :slot_count

    def initialize(total_duration: 0.0, counted_duration: 0.0, credits: 0.0, slot_count: 0)
      @total_duration = total_duration
      @counted_duration = counted_duration
      @credits = credits
      @slot_count = slot_count
    end
  end


  module_function

  # Count the number of signups which earns credits or is not a training shift
  #
  # @param person [Person]
  # @return [ShiftSignupsSummary]
  def summarize_shift_signups(person)
    year = Current.year
    rows, positions = Scheduling::Query.find_for_query(person.id, year, only_signups: true, positions_by_id: true)

    positions_by_id = positions.transform_keys(&:to_i)

    rows = rows.select do |r|
      r.credits.positive? || positions_by_id[r.position_id.to_i]&.type != Position::TYPE_TRAINING
    end

    total_duration = 0.0
    counted_duration = 0.0
    credits = 0.0

    rows.each do |row|
      credits += row.credits
      total_duration += row.slot.duration
      counted_duration += row.slot.duration if positions_by_id[row.position.id]&.count_hours
    end

    ShiftSignupsSummary.new(
      total_duration: total_duration,
      counted_duration: counted_duration,
      credits: credits,
      slot_count: rows.size
    )
  end

  # Build a schedule summary (credit/hour break down by event period)
  #
  # @param person_id [Integer]
  # @param year [Integer]
  # @param remaining [Boolean]
  # @return [ScheduleSummary]
  def schedule_summary_for_person_year(person_id, year, remaining: false)
    query = { only_signups: true }
    query[:remaining] = true if remaining

    now = Current.time
    rows, positions = Scheduling::Query.find_for_query(person_id, year, query)
    event_dates = EventDate.find_for_year(year)

    return build_summary_without_event_dates(rows) unless event_dates

    summary = EventSummary.new(event_dates.event_start.to_i, event_dates.event_end.to_i, year)
    positions_by_id = positions.index_by(&:id)

    rows.each do |row|
      # begins_time is a unix timestamp, so the shift under way is found against now.to_i.
      if remaining && row.slot.begins_time < now.to_i
        # Adjust the start time to figure out what could be earned for the
        # remaining time on playa.
        row.slot.begins = now
        row.slot.begins_time = now.to_i
      end
      position = positions_by_id[row.position_id]
      summary.compute_totals(row.position_id, row.slot.begins_time, row.slot.ends_time, position.count_hours)
    end

    build_schedule_summary(summary, event_dates, person_id, year)
  end

  # Build summary when no event dates are found
  def build_summary_without_event_dates(rows)
    time = rows.sum { |row| row.slot.duration }
    credits = rows.sum(&:credits)

    ScheduleSummary.new(
      event_duration: time,
      event_credits: credits,
      total_duration: time,
      total_credits: credits
    )
  end

  # Build the schedule summary from work summary
  def build_schedule_summary(summary, event_dates, person_id, year)
    ScheduleSummary.new(
      pre_event_duration: summary.pre_event_duration,
      pre_event_credits: summary.pre_event_credits,
      event_duration: summary.event_duration,
      event_credits: summary.event_credits,
      post_event_duration: summary.post_event_duration,
      post_event_credits: summary.post_event_credits,
      total_duration: summary.pre_event_duration + summary.event_duration +
        summary.post_event_duration + summary.other_duration,
      total_credits: summary.pre_event_credits + summary.event_credits +
        summary.post_event_credits,
      other_duration: summary.other_duration,
      counted_duration: summary.pre_event_duration + summary.event_duration +
        summary.post_event_duration,
      event_start: event_dates.event_start,
      event_end: event_dates.event_end,
      credits_earned: Timesheet.earned_credits_for_year(person_id, year)
    )
  end

  # Build shift info for starting slots
  def build_shift_info(row, slot, early_time, within_start, now, start)
    shift = ShiftInfo.new(
      slot_id: row.slot_id,
      slot_description: slot.description,
      position_id: slot.position_id,
      position_title: slot.position.title,
      slot_begins: slot.begins,
      slot_ends: slot.ends,
      slot_timezone: slot.timezone,
      slot_info: slot.url,
      is_within_start_time: early_time.zero? || within_start
    )

    unless within_start
      can_start_in = ((start - now) / 60).to_i
      shift.can_start_in = [can_start_in, 1].max
    end

    shift
  end
end
