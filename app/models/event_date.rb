# frozen_string_literal: true

class EventDate < ApplicationRecord
  self.audit_model = true

  # On playa operation periods
  PRE_EVENT_OPS = "pre"
  POST_EVENT_OPS = "post"
  EVENT_WEEK_OPS = "event"

  # Event cycle periods throughout the year wrt the {Ranger,PNV,Auditor} dashboards.
  # (not to be confused with the {pre,post}-event weeks.)
  AFTER_EVENT = "after-event"
  BEFORE_EVENT = "before-event"
  EVENT = "event"

  # Every date belongs to the event year, except the end of the credit period:
  # it closes at the top of the following January, so it may fall in either.
  # The label is carried here because errors.format drops the attribute name.
  SAME_YEAR_AS_EVENT = {
    event_end: "Event End",
    pre_event_start: "Pre-Event Start",
    pre_event_slot_start: "Pre-Event Slot Start",
    pre_event_slot_end: "Pre-Event Slot End"
  }.freeze

  # Validations
  validates :event_end, presence: true
  validates :event_start, presence: true
  validates :post_event_end, presence: true
  validates :pre_event_slot_end, presence: true
  validates :pre_event_slot_start, presence: true
  validates :pre_event_start, presence: true

  # Each window runs forwards, and the credit period contains the event it
  # credits. A pair with a missing half is left to the presence validations,
  # which already say what is wrong with it.
  validates :event_end,
            comparison: { greater_than: :event_start, message: "Event End must be after the Event Start" },
            allow_nil: true, if: -> { event_start.present? }
  validates :pre_event_slot_end,
            comparison: { greater_than: :pre_event_slot_start,
                          message: "Pre-Event Slot End must be after the Pre-Event Slot Start" },
            allow_nil: true, if: -> { pre_event_slot_start.present? }
  validates :event_start,
            comparison: { greater_than_or_equal_to: :pre_event_start,
                          message: "Pre-Event Start must be on or before the Event Start" },
            allow_nil: true, if: -> { pre_event_start.present? }
  validates :post_event_end,
            comparison: { greater_than_or_equal_to: :event_end,
                          message: "Post-Event End must be on or after the Event End" },
            allow_nil: true, if: -> { event_end.present? }

  validate :dates_belong_to_the_event_year
  validate :event_year_is_not_already_recorded

  # Scopes
  scope :ordered, -> { order(:event_start) }
  scope :for_year, ->(year) { where_year("event_start", year) }

  #
  # Find the event date record for a given year
  #
  # @param year [Integer] the year to search for
  # @return [EventDate, nil]
  #
  def self.find_for_year(year)
    for_year(year).first
  end

  #
  # Calculate what the event period is for the dashboard.
  #
  # - before-event: March 1st til gate opening
  # - event: gate opening til Saturday @ noon after Labor Day.
  # - after-event: Saturday @ noon after Labor Day til March 1st
  #
  # @return [String]
  #
  def self.calculate_period
    period_setting = Setting.get_value(Setting::DASHBOARD_PERIOD)
    return period_setting if period_setting.present? && period_setting != "auto"

    now = Current.time
    return AFTER_EVENT if now.month < 3

    year = now.year
    labor_day = first_monday_of_september(year)

    # Figure out when the Saturday after Labor Day is
    final_saturday = (labor_day + 5.days).change(hour: 12, min: 0, sec: 0)
    return AFTER_EVENT if final_saturday <= now

    # Gate open is the Sunday a week before Labor Day
    gate_open = (labor_day - 8.days).beginning_of_day
    return EVENT if gate_open <= now

    BEFORE_EVENT
  end

  #
  # Retrieve the burn weekend date range.
  #
  # @return [BurnWeekendPeriod] start and ending time
  #
  def self.retrieve_burn_weekend_period
    year = Current.year
    labor_day = first_monday_of_september(year)

    # Burn weekend is Friday @ 18:00 til Monday @ 00:00 (late Sunday night)
    start_time = (labor_day - 3.days).change(hour: 18, min: 0, sec: 0)
    end_time = labor_day.beginning_of_day

    [start_time, end_time]
  end

  #
  # Calculate days until Man Burn (Saturday before Labor Day)
  #
  # @return [Integer] number of days until Man Burn (rolls over to next year after event passes)
  #
  def self.days_until_man_burn
    year = Current.year
    labor_day = first_monday_of_september(year)
    man_burn_day = (labor_day - 2.days).to_date  # Saturday before Labor Day
    today = Current.today

    # If this year's Man Burn has passed, calculate for next year
    if today > man_burn_day
      labor_day = first_monday_of_september(year + 1)
      man_burn_day = (labor_day - 2.days).to_date
    end

    (man_burn_day - today).to_i
  end

  #
  # Retrieve the event period (pre, event week, post)
  #
  # @return [String]
  #
  def self.retrieve_event_ops_period
    year = Current.year
    event_dates = find_for_year(year)
    now = Current.time

    if event_dates
      if event_dates.event_start > now
        return PRE_EVENT_OPS
      elsif event_dates.event_end <= now
        return POST_EVENT_OPS
      else
        return EVENT_WEEK_OPS
      end
    end

    labor_day = first_monday_of_september(year)

    # Work backwards
    return POST_EVENT_OPS if labor_day <= now

    july15 = Time.zone.local(year, 7, 15)
    return BEFORE_EVENT if july15 >= now

    gate_open = labor_day - 8.days
    return PRE_EVENT_OPS if gate_open > now

    EVENT_WEEK_OPS
  end

  #
  # Find the first Monday of September for a given year (Labor Day in the US)
  #
  # @param year [Integer]
  # @return [Time]
  #
  def self.first_monday_of_september(year)
    sept_1 = Date.new(year, 9, 1)
    labor_day = sept_1.monday? ? sept_1 : sept_1.next_occurring(:monday)
    labor_day.in_time_zone
  end

  private

  # A mistyped year puts a whole event in the wrong place, and nothing else
  # here would catch it.
  def dates_belong_to_the_event_year
    return if event_start.blank?

    year = event_start.year

    SAME_YEAR_AS_EVENT.each do |column, label|
      value = self[column]
      next if value.blank? || value.year == year

      errors.add(column, "#{label} must be in #{year}, the same year as the Event Start")
    end

    return if post_event_end.blank?
    return if post_event_end.year == year
    return if post_event_end.year == year + 1 && post_event_end.month == 1

    errors.add(:post_event_end, "Post-Event End must be in #{year} or January #{year + 1}")
  end

  # Every reader resolves a year with find_for_year, which keeps the first row
  # and ignores the rest, so a second record for one year is invisible work.
  def event_year_is_not_already_recorded
    return if event_start.blank?

    clash = EventDate.for_year(event_start.year)
    clash = clash.where.not(id:) if persisted?
    return unless clash.exists?

    errors.add(:event_start, "#{event_start.year} already has an event date record")
  end
end
