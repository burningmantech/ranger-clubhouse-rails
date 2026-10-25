# frozen_string_literal: true

# Shared plumbing for the HQ Window Interface controllers (/hq/:person_id/...).
# Ported from the Ember hq parent route (port/routes/hq.js + port/templates/hq.hbs):
# gates on the HQWindowInterfaceEnabled setting (its first consumer) and on the
# Admin / Shift Management roles, loads the subject person, and assembles the
# shell data the "hq" layout chrome renders around every child page.
#
# Always operates on the current year — the HQ shell has no year selector,
# matching upstream.
module HqConcern
  extend ActiveSupport::Concern

  # Ember reads summary.counted_duration and summary.total_credits from the
  # person/N/timesheet-summary payload; the Rails equivalent is composed from
  # EventSummaryReport plus the entry credits sum (what
  # Timesheet.earned_credits_for_year computes).
  #
  # Carried in @hq_summary, NOT @summary: the shell chrome renders around every
  # child page, including pages from shared concerns mounted in this namespace,
  # and @summary is those pages' own convention (ScheduleConcern#signup_summary,
  # Person::TimesheetsController#breakdown, Me::EventSummaryController). A page
  # assigning @summary would silently repaint this column with its own figures —
  # Scheduling::Summaries::ScheduleSummary even answers both members, so the
  # column would render SCHEDULED hours under the "Earned" label rather than
  # raise. Any new ivar this concern adds must stay hq_-prefixed for the same
  # reason.
  TimesheetSummary = Data.define(:counted_duration, :total_credits)

  included do
    layout "hq"

    # Deliberate deviation from port/api/*Policy.php, decided 2026-07-21: the
    # Laravel policies wanted Event Management (or Admin/Edit Assets) for asset
    # checkout and Admin/Event Management for pogs, but upstream's own UI showed
    # both to every Shift Management holder and only blocked at the API. Since
    # issuing a radio is the point of the site-registration wizard, the window
    # worker's role carries it. Pinned by the HQ controller tests, which grant
    # Shift Management alone and expect a successful checkout.
    authorize_role [Role::ADMIN, Role::SHIFT_MANAGEMENT],
                   message: "You do not have either the Admin or Shift Management permissions."

    before_action :set_person
    before_action :require_hq_window_interface
    before_action :load_hq_shell
  end

  private

  # Feature gate — the HQ Window Interface is only turned on while on-playa
  # event operations are running.
  def require_hq_window_interface
    return true if Setting.get_value(Setting::HQ_WINDOW_INTERFACE_ENABLED)

    redirect_to person_path(@person), error: "The HQ Window Interface is not currently available."
    false
  end

  # Same shape as PersonConcern#set_person; HQ routes always carry :person_id.
  def set_person
    unless (@person = Person.find_by(id: params[:person_id]))
      redirect_to me_root_path, error: "Person not found"
      return false
    end

    true
  end

  # Loads the data shared by the HQ shell chrome (header, banner strip, danger
  # notices, photo/summary column, warning modals). Controllers that never
  # render the shell (the index redirector, the tickets-provisions modal) skip
  # this with skip_before_action :load_hq_shell.
  def load_hq_shell
    year = Current.year

    @person_event = PersonEvent.first_or_new_for_person_year(@person.id, year)
    @event_info = PersonEventInfo.find_for_person_year(@person, year)
    @event_periods = build_event_periods(@event_info)
    @banners = PersonBanner.find_for_query(person_id: @person.id, active: true)
    @hq_email_suppression = EmailSuppression.find_by(email: @person.email)
    # The one shell ivar deliberately left unprefixed: MessagesHelper memoizes
    # into this same name, and on Hq::MessagesController its message_owner IS
    # @person, so the two values are identical and the sharing saves a query.
    @unread_message_count = PersonMessage.count_unread(@person.id)
    @photo = PersonPhoto.retrieve_info(@person)
    @hq_summary = build_timesheet_summary(year)

    # Viewer (HQ worker) on-duty state — drives the sign-in warning modal and
    # the mentor-only allowances for Alphas/Prospectives.
    @viewer_on_duty = Current.onduty_entry.present?
    @viewer_is_mentor = Current.onduty_position_subtype == "mentor"

    # The auto-shown warning modals fire once per person per session, matching
    # the Ember shell where they open on route entry, not on every action's
    # redirect back to the page.
    @show_entry_warnings = session[:hq_warned_person_id] != @person.id
    session[:hq_warned_person_id] = @person.id

    true
  end

  # {pre:, event:, post:} each {current:, has_pass:} — derived exactly as the
  # Ember parent's setupController does from event-info: current from
  # event_period (guarded, since "before-event"/"after-event" have no row) and
  # has_pass per period from the BMID meal package.
  def build_event_periods(event_info)
    periods = [:pre, :event, :post].index_with { { current: false, has_pass: false } }

    current = event_info&.event_period&.to_sym
    periods[current][:current] = true if periods.key?(current)

    meals = event_info&.meals
    periods.each_key { |key| periods[key][:has_pass] = true if meals&.public_send(key) } if meals

    periods
  end

  def build_timesheet_summary(year)
    rows = Timesheet.find_for_query(person_id: @person.id, year:)
    report = EventSummaryReport.execute(@person.id, year, rows:)

    TimesheetSummary.new(
      counted_duration: report.counted_duration,
      total_credits: rows.sum(&:credits)
    )
  end
end
