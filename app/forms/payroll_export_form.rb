# frozen_string_literal: true

# The pay window and meal-break rules a payroll export is built from.
#
# Times are held as the strings the date fields send and parsed on demand. The
# database stores wall-clock times, so what the clerk types is what is compared
# and what ends up in the file -- no zone conversion anywhere along the way.
class PayrollExportForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "payroll"

  # The value a date field wants back when the page is redrawn.
  FIELD_FORMAT = "%Y-%m-%dT%H:%M"

  # Far longer than any pay period, and short enough that a year typed wrong
  # cannot ask for the whole timesheet table.
  MAX_WINDOW = 90.days

  BREAK_AFTER_OPTIONS = [["None", 0], ["4 hours", 4], ["5 hours", 5],
                         ["6 hours", 6], ["7 hours", 7]].freeze
  BREAK_DURATION_OPTIONS = [["30 mins", 30], ["60 mins", 60],
                            ["75 mins", 75], ["90 mins", 90]].freeze

  attribute :start_time, :string
  attribute :end_time, :string
  # Held as sent, like the dates above, and checked against the offered list
  # before being read as a number. An integer attribute would cast anything
  # unparseable to 0 -- and 0 is itself an offered value meaning "no meal
  # breaks", so a mistyped link would turn breaks off with nothing to notice.
  attribute :break_after, :string, default: "4"
  attribute :break_duration, :string, default: "60"
  # Narrows the page to one person. Not part of what the report asks for.
  attribute :person_id, :integer
  attribute :position_ids, IdList::Type.new, default: -> { [] }

  # Held to the choices the page offers, not merely to "not negative". An
  # integer attribute turns anything unparseable into 0, and 0 means no meal
  # breaks at all -- so a mistyped or stale link would quietly produce a payroll
  # file with none deducted, while the folded summary reported "No meal breaks"
  # as though it had been chosen. A zero length would also punch out to lunch
  # and back at the same instant.
  #
  # Each message names its own field: the error summary prints the message
  # alone, so one that does not say what it is about leaves the reader hunting.
  validates :break_after, inclusion: {
    in: BREAK_AFTER_OPTIONS.map { |(_, value)| value.to_s },
    message: "Choose one of the offered meal break thresholds."
  }
  validates :break_duration, inclusion: {
    in: BREAK_DURATION_OPTIONS.map { |(_, value)| value.to_s },
    message: "Choose one of the offered meal break lengths."
  }
  validate :window_makes_sense
  validate :positions_chosen

  def parsed_start_time = parse(start_time)

  def parsed_end_time = parse(end_time)

  # Safe to read as numbers only because validation has held both to the
  # offered lists.
  def break_after_hours = break_after.to_i

  def break_duration_minutes = break_duration.to_i

  # Opens on the week payroll is about to be run for: the seven days ending at
  # the most recent Sunday midnight, which is the last week to have finished.
  def self.with_defaults(position_ids:)
    week_end = Current.time.beginning_of_week(:sunday)

    new(start_time: (week_end - 1.week).strftime(FIELD_FORMAT),
        end_time: week_end.strftime(FIELD_FORMAT),
        position_ids:)
  end

  # Everything needed to rebuild this page, for export links and the person
  # filter. Nested so one query parameter holds the whole request.
  def query_params
    { PARAM_SCOPE => {
      start_time:,
      end_time:,
      break_after:,
      break_duration:,
      position_ids:,
      person_id: person_id.presence
    }.compact }
  end

  # Names the window for a downloaded file, e.g. "2026-08-09-to-2026-08-16".
  def window_slug
    from, to = parsed_start_time, parsed_end_time
    return "window" unless from && to

    "#{from.strftime("%Y-%m-%d")}-to-#{to.strftime("%Y-%m-%d")}"
  end

  private

  def parse(value)
    return nil if value.blank?

    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end

  def window_makes_sense
    from = parsed_start_time
    to = parsed_end_time

    errors.add(:start_time, "Enter the date and time the pay period starts.") if from.nil?
    errors.add(:end_time, "Enter the date and time the pay period ends.") if to.nil?
    return if from.nil? || to.nil?

    return errors.add(:end_time, "The end of the pay period has to come after the start.") if to <= from

    # A mistyped year is the ordinary way this goes wrong, and an unbounded
    # window reads every timesheet entry ever recorded before anyone notices.
    return if (to - from) <= MAX_WINDOW

    errors.add(:end_time, "A pay period cannot be longer than #{MAX_WINDOW.inspect}.")
  end

  def positions_chosen
    return if position_ids.any?

    errors.add(:position_ids, "Choose at least one position to report on.")
  end
end
