# frozen_string_literal: true

# Every shift sign-up of an event year, grouped by callsign (Ember
# reports/schedule-by-callsign port). The roster drills down into one person's
# shifts, as its timesheet sibling does -- upstream stacked eight hundred people
# onto one page as accordions.
class Scheduling::ScheduleByCallsignController < ApplicationController
  include CsvExportConcern

  layout "scheduling"

  # Upstream SlotPolicy: the before hook admits Admin and Edit Slots, and
  # report() admits Event Management. The same triple the Flake Report spells --
  # it hangs off this same policy, and reading the before hook is the only way
  # to see that Edit Slots ever reaches report() at all.
  authorize_role [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT],
                 message: "Admin, Edit Slots, or Event Management role required " \
                          "to view the schedule by callsign."

  # Upstream's own YearSelect floor.
  self.year_floor = 2008

  # One wording for "no such person" and for a person with nothing to show, so
  # the two cannot be told apart from the outside.
  PERSON_NOT_FOUND = "The person could not be found."

  before_action :setup_year
  before_action :set_person, only: :person

  def index
    @report = ScheduleByCallsignReport.summary(year: @year)

    respond_to do |format|
      format.html do
        # Assigned for the select, which orders its options by the whole
        # roster's counts so they do not reshuffle as the callsign filter
        # changes. filter_params reads the same memo, in either order.
        @status_counts = status_counts
        @filter_params = filter_params

        # Narrowed in two steps rather than filtering the whole roster twice:
        # the status labels describe exactly this set, and the roster below is
        # that same set with the chosen status kept. filtered_people ignores a
        # filter it is not given, so the second pass re-applying the callsign
        # would be a no-op -- it is handed the whole set for readability.
        matching = filtered_people(@report, @filter_params.except(:status))
        @matching_status_counts = count_by_status(matching)
        @people = filtered_people(matching, @filter_params)
      end

      format.csv do
        send_csv(summary_csv_rows(@report), filename: "#{@year}-schedule-by-callsign.csv")
      end
    end
  end

  def person
    @detail = ScheduleByCallsignReport.person(year: @year, person_id: @person.id)
    return if hidden_person_redirect

    respond_to do |format|
      format.html
      format.csv do
        send_csv(person_csv_rows(@detail),
                 filename: "#{@year}-#{@person.callsign.parameterize}-schedule.csv")
      end
    end
  end

  private

  def set_person
    @person = Person.find_by(id: params[:person_id])
    return if @person

    redirect_to scheduling_schedule_by_callsign_path(year: @year), error: PERSON_NOT_FOUND
  end

  # Edit Slots reads this report but is deliberately NOT in
  # PersonConcern::VIEW_ROLES, so /person/:id is closed to them. This page must
  # not become that page by another name: an id with no sign-ups is not on the
  # roster, so reaching it means typing the URL, and rendering it would put the
  # callsign in the heading and confirm the account exists. Turned back with the
  # same wording a missing id gets, so the two cannot be told apart.
  #
  # Only for a reader who cannot open person pages anyway. For everyone else an
  # empty year is a true and useful page -- and bouncing them would break the
  # year selector, which is how a reader asks "did they ranger in 2019?".
  def hidden_person_redirect
    return false if Current.has_role?(PersonConcern::VIEW_ROLES)
    return false if @detail.slots.any?

    redirect_to scheduling_schedule_by_callsign_path(year: @year), error: PERSON_NOT_FOUND
    true
  end

  # Only the filters actually narrowing the roster, so the chips and the
  # clear-all link agree about what is applied. The CSV is deliberately not in
  # that list: it exports the whole roster, which is what its button says.
  #
  # The status is checked against the statuses the roster actually holds, the
  # way the Shift Lead Report checks every one of its filters. The select is
  # built from those same statuses, so an unrecognised one -- a stale bookmark,
  # a typo, `?status[]=x` -- would otherwise draw a chip claiming to narrow the
  # roster to no one while the select beside it still read "All".
  #
  # The callsign has no such vocabulary to check against, so it is demanded as
  # a String: `?callsign[]=x` hands back an Array, which is neither blank nor
  # the sentinel and would survive into a chip reading `Callsign: ["x"]`.
  # No argument: the vocabulary is derived in here, off the roster, the way the
  # Shift Lead Report derives every one of its filters. Taking the allowed set
  # as a parameter meant the caller had to build @status_counts first and pass
  # the right one of the two count hashes -- passing @matching_status_counts
  # would silently reset a valid status to "all" whenever the callsign filter
  # had narrowed that status away, with the chip and the select agreeing on the
  # wrong answer.
  def filter_params
    UiComponents::FilterBarHelper.active_filters(
      callsign: string_param(:callsign),
      # string_param first, so the status is trimmed and type-checked before the
      # lookup -- known_filter compares with include?, and " active " matches
      # nothing, which would silently drop a filter the reader can see they set.
      status: UiComponents::FilterBarHelper.known_filter(string_param(:status),
                                                         status_counts.keys)
    )
  end

  # Memoized: the roster is counted by status for the select's ordering, and
  # again through filter_params for the vocabulary it validates against.
  def status_counts
    @status_counts ||= count_by_status(@report)
  end

  def string_param(key)
    value = params[key]
    value.is_a?(String) ? value.strip.presence : nil
  end

  def count_by_status(people)
    people.group_by(&:person_status).transform_values(&:size)
  end

  # Filtered in Ruby: the roster is already loaded in full to total it, and a
  # second trip to the database could only disagree with the totals on screen.
  #
  # Filters arrive as an argument rather than off the ivar so the caller can ask
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

  # The roster's own columns. Upstream has no export at all; this one carries
  # what the roster shows so a reader can sort by hours, which the page does not.
  #
  # NOT getlocal, though the sibling exports spell it that way. getlocal re-reads
  # the value in the host's zone, which for a shift near midnight names the day
  # before -- so the roster read "Feb 17" while the export button beside it wrote
  # "Feb 16" for that same row. An export is the page in another format, and the
  # two have to agree; Time.zone is what every rendered surface here shows.
  def summary_csv_rows(people)
    # "Begins"/"Ends", matching the person export's columns: the two dates bound
    # the person's event, so the second one is when their last shift LEAVES, not
    # when it starts. A column headed "Last Shift" holding an end time is a
    # number a reader would quietly misread.
    rows = [["Callsign", "Status", "Shifts", "Hours",
             "First Shift Begins", "Last Shift Ends"]]

    people.each do |row|
      rows << [row.callsign, row.person_status, row.shift_count,
               helpers.hour_format(row.total_duration),
               row.first_begins.iso8601, row.last_ends.iso8601]
    end

    rows
  end

  # One row per shift, in the order the page lists them.
  def person_csv_rows(detail)
    rows = [["Callsign", "Status", "Shift Begins", "Shift Ends", "Duration",
             "Description", "Position", "Position Active"]]

    detail.slots.each do |slot|
      # position, alone, keeps its nil guard: position_id is NOT NULL, but the
      # Laravel-shared schema carries no foreign keys, so the row it names can
      # be gone.
      #
      # Time.zone rather than getlocal, for the reason given above the roster
      # export: this file has to name the same day the table above it does.
      rows << [@person.callsign, @person.status,
               slot.begins.iso8601, slot.ends.iso8601,
               helpers.hour_format(slot.duration),
               slot.description,
               slot.position&.title,
               # Blank, not "N", when the position row is gone: "N" is a claim
               # that the position is retired, and a reader sorting on this
               # column would file every unknown under genuine retirements.
               slot.position ? (slot.position.active ? "Y" : "N") : nil]
    end

    rows
  end
end
