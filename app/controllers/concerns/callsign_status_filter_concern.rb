# frozen_string_literal: true

# The callsign-contains + person-status filter shared by the timesheet roster
# pages keyed on a person row (Timesheets by Callsign, Timesheet Totals).
# Timesheet by Position filters a different shape of row (title + active) and
# does not use this.
module CallsignStatusFilterConcern
  extend ActiveSupport::Concern

  private

  # Demanded as a String: `?status[]=x` hands back an Array and `?status[a]=b`
  # an ActionController::Parameters, neither of which is blank nor the "all"
  # sentinel, so both would survive as an active filter that matches no one
  # and draws a chip reading `Status: ["x"]`.
  def string_param(key)
    value = params[key]
    value.is_a?(String) ? value.strip.presence : nil
  end

  def filter_params
    UiComponents::FilterBarHelper.active_filters(
      callsign: string_param(:callsign),
      status: string_param(:status)
    )
  end

  def count_by_status(people)
    people.group_by(&:person_status).transform_values(&:size)
  end

  # Filtered in Ruby: the roster is already loaded in full to total it, and a
  # second trip to the database could only disagree with the totals on screen.
  #
  # Filters arrive as an argument rather than off an ivar so the caller can ask
  # for a partial set -- the status counts need the roster narrowed by
  # everything except status.
  def filtered_people(people, filters)
    callsign = filters[:callsign]&.downcase
    status = filters[:status]

    people.select do |row|
      (callsign.nil? || row.callsign.downcase.include?(callsign)) &&
        (status.nil? || row.person_status == status)
    end
  end
end
