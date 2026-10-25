# frozen_string_literal: true

module EventDatesHelper
  # One of a record's three date windows. Every column is nullable, and a
  # half-set pair would otherwise render as a lone timestamp that reads like a
  # deliberate single instant -- or, when the start is the missing half, as a
  # blank cell that drops an end date the record does have. Both halves have to
  # be present before the range means anything.
  #
  # @param start_time [Time, nil] the window's start
  # @param end_time [Time, nil] the window's end
  # @param year [Boolean] stamp the year on both ends, for a window that may
  #   legitimately open and close in the same year or straddle two
  # @return [String] the formatted range, or a "Not set" badge
  def event_date_window(start_time, end_time, year: false)
    unless start_time && end_time
      return ui_badge("Not set", :secondary, icon: "circle-minus", icon_type: :solid)
    end

    datetime_format(start_time, end_time, year:)
  end
end
