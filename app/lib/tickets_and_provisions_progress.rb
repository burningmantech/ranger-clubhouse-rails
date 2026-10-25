# frozen_string_literal: true

# Tickets and Provisions Progress class
# Calculates what tickets and provisions (meals, showers, clothing) a person
# has earned based on work done already, what they might be expected to earn
# based on remaining scheduled signups, and how much credits/hours they are
# short in signups.
class TicketsAndProvisionsProgress
  include DateTimeHelper
  include CreditHelper

  # Measurement types
  MEASURE_CREDITS = :credits
  MEASURE_HOURS = :hours

  # Item type constants
  ITEM_STAFF_CREDENTIAL = :staff_credential
  ITEM_SPT = :spt
  ITEM_SHOWER_POG = :shower_pog
  ITEM_SHOWER_ACCESS_ENTIRE_EVENT = :shower_access_entire_event
  ITEM_SHOWER_ACCESS_EVENT_WEEK = :shower_access_event_week
  ITEM_EVENT_WEEK_MEAL_PASS = :event_week_eats
  ITEM_ALL_EAT_PASS = :all_eats
  ITEM_TSHIRT = :t_shirt
  ITEM_LONG_SLEEVE_SHIRT = :long_sleeve_shirt

  # The running totals an item can read (ProgressItem#counter).
  COUNTERS = %i[credits all_hours event_week pre_event_and_event_week].freeze

  THRESHOLD_SETTINGS = [
    Setting::ALL_YOU_CAN_EAT_EVENT_WEEK_THRESHOLD,
    Setting::ALL_YOU_CAN_EAT_EVENT_PERIOD_THRESHOLD,
    Setting::SC_TICKET_THRESHOLD,
    Setting::SP_TICKET_THRESHOLD,
    Setting::SHOWER_POG_THRESHOLD,
    Setting::SHOWER_ACCESS_ENTIRE_EVENT_THRESHOLD,
    Setting::SHOWER_ACCESS_EVENT_WEEK_THRESHOLD,
    Setting::SHIRT_LONG_SLEEVE_HOURS_THRESHOLD,
    Setting::SHIRT_SHORT_SLEEVE_HOURS_THRESHOLD
  ].freeze

  # Progress item class representing earned/expected status for a single provision type
  class ProgressItem
    attr_accessor :name,
                  :measure,
                  :value,
                  :expected_total,
                  :threshold,
                  :has_earned,
                  :expected_to_earn,
                  :needs_to_work,
                  :needs_to_schedule,
                  :percentage,
                  :projected_percentage,
                  # Which running total the item reads: :credits, :all_hours,
                  # :event_week, or :pre_event_and_event_week
                  :counter,
                  # How far sign-ups fall short of the threshold, as a number in the
                  # threshold's unit (hours or credits); zero or less once on track
                  :shortfall,
                  # True once the counter can no longer grow this year, so no
                  # sign-up can earn the item (see closed_counters)
                  :closed

    def initialize(name:, measure:, value:, expected_total:, threshold:,
                   has_earned:, expected_to_earn:, needs_to_work:, needs_to_schedule:)
      @name = name
      @measure = measure
      @value = value
      @expected_total = expected_total
      @threshold = threshold
      @has_earned = has_earned
      @expected_to_earn = expected_to_earn
      @needs_to_work = needs_to_work
      @needs_to_schedule = needs_to_schedule
      @percentage = 0
      @projected_percentage = 0
    end
  end

  attr_reader :items, :ineligible_duration, :is_shiny_penny

  # Compute the tickets and provisions progress for a person
  #
  # @param person [Person] The person to compute progress for
  # @return [TicketsAndProvisionsProgress] The computed progress
  # rubocop:disable Metrics/AbcSize
  def initialize(person)
    @items = {}

    year = Current.year
    person_id = person.id

    thresholds = Setting.get_value(THRESHOLD_SETTINGS)

    timesheet_summary = EventSummaryReport.execute(person_id, year)
    # remaining: only sign-ups still ahead count as expected -- an ended shift is
    # already on the timesheet or was missed, and a shift under way counts from now.
    remaining = Scheduling::Summaries.schedule_summary_for_person_year(person_id, year, remaining: true)

    credits = timesheet_summary.total_credits
    expected_credits = credits + remaining.total_credits
    hours = timesheet_summary.counted_duration
    expected_hours = hours + remaining.total_duration
    pre_event_and_event_hours = timesheet_summary.pre_event_duration +
                                timesheet_summary.event_duration
    expected_pre_event_and_event_hours = pre_event_and_event_hours +
                                         remaining.pre_event_duration +
                                         remaining.event_duration

    calculate_item(
      ITEM_SPT,
      credits, expected_credits,
      thresholds[Setting::SP_TICKET_THRESHOLD], MEASURE_CREDITS, counter: :credits
    )

    calculate_item(
      ITEM_STAFF_CREDENTIAL,
      credits, expected_credits,
      thresholds[Setting::SC_TICKET_THRESHOLD], MEASURE_CREDITS, counter: :credits
    )

    calculate_item(
      ITEM_ALL_EAT_PASS,
      hours, expected_hours,
      thresholds[Setting::ALL_YOU_CAN_EAT_EVENT_PERIOD_THRESHOLD], MEASURE_HOURS, counter: :all_hours
    )

    event_duration = timesheet_summary.event_duration
    expected_event_duration = event_duration + remaining.event_duration

    calculate_item(
      ITEM_EVENT_WEEK_MEAL_PASS,
      event_duration, expected_event_duration,
      thresholds[Setting::ALL_YOU_CAN_EAT_EVENT_WEEK_THRESHOLD], MEASURE_HOURS, counter: :event_week
    )

    calculate_item(
      ITEM_SHOWER_POG,
      event_duration, expected_event_duration,
      thresholds[Setting::SHOWER_POG_THRESHOLD], MEASURE_HOURS, counter: :event_week
    )

    calculate_item(
      ITEM_SHOWER_ACCESS_EVENT_WEEK,
      event_duration, expected_event_duration,
      thresholds[Setting::SHOWER_ACCESS_EVENT_WEEK_THRESHOLD], MEASURE_HOURS, counter: :event_week
    )

    calculate_item(
      ITEM_SHOWER_ACCESS_ENTIRE_EVENT,
      hours, expected_hours,
      thresholds[Setting::SHOWER_ACCESS_ENTIRE_EVENT_THRESHOLD], MEASURE_HOURS, counter: :all_hours
    )

    calculate_item(
      ITEM_TSHIRT,
      pre_event_and_event_hours, expected_pre_event_and_event_hours,
      thresholds[Setting::SHIRT_SHORT_SLEEVE_HOURS_THRESHOLD], MEASURE_HOURS, counter: :pre_event_and_event_week
    )

    calculate_item(
      ITEM_LONG_SLEEVE_SHIRT,
      pre_event_and_event_hours, expected_pre_event_and_event_hours,
      thresholds[Setting::SHIRT_LONG_SLEEVE_HOURS_THRESHOLD], MEASURE_HOURS, counter: :pre_event_and_event_week
    )

    closed = self.class.closed_counters
    @items.each_value { |item| item.closed = closed.include?(item.counter) }

    @ineligible_duration = timesheet_summary.other_duration
    @is_shiny_penny = Timesheet.alpha_entry?(person_id) && person.status == Person::ACTIVE
  end

  # The counters whose hours or credits can no longer come from a sign-up this
  # year: the Event Week and Pre-Event + Event Week totals once event week has
  # ended, and every total once post-event ends. Nothing closes while the year's
  # event dates are unknown, beyond what the ops-period fallback says.
  def self.closed_counters
    post_event_end = EventDate.find_for_year(Current.year)&.post_event_end
    return COUNTERS if post_event_end && post_event_end <= Current.time

    EventDate.retrieve_event_ops_period == EventDate::POST_EVENT_OPS ? %i[event_week pre_event_and_event_week] : []
  end

  # Calculate progress for a single item type
  #
  # @param item [Symbol] The item type constant
  # @param value [Numeric] Current value (credits or seconds)
  # @param expected_total [Numeric] Expected value including scheduled work
  # @param threshold [Numeric] Threshold to earn the item
  # @param measure [Symbol] MEASURE_CREDITS or MEASURE_HOURS
  # @param counter [Symbol] the running total value and expected_total come from
  def calculate_item(item, value, expected_total, threshold, measure, counter:)
    is_hours = measure == MEASURE_HOURS
    threshold_adjusted = is_hours ? threshold * 3600 : threshold

    has_earned = value >= threshold_adjusted
    expected_earn = expected_total >= threshold_adjusted

    progress = ProgressItem.new(
      name: item,
      measure:,
      value:,
      expected_total:,
      threshold:,
      has_earned:,
      expected_to_earn: expected_earn,
      needs_to_work: has_earned ? 0 : (threshold_adjusted - value),
      needs_to_schedule: (has_earned || expected_earn) ? 0 : threshold_adjusted - expected_total
    )

    progress.percentage = percent_of(value, threshold_adjusted)
    progress.projected_percentage = percent_of(expected_total, threshold_adjusted)
    progress.counter = counter
    progress.shortfall = (threshold_adjusted - expected_total) / (is_hours ? 3600.0 : 1)

    @items[item] = progress

    [:value, :expected_total, :needs_to_work, :needs_to_schedule].each do |key|
      value = progress.send(key)
      progress.send("#{key}=", is_hours ? hour_minute_words(value, full: true) : credit_format(value.to_f))
    end
  end

  private

  # Whole percent of the threshold, capped at 100. A zero threshold is already met.
  def percent_of(amount, threshold)
    return 100 unless threshold.positive?

    [(amount.to_f / threshold * 100).round, 100].min
  end
end
