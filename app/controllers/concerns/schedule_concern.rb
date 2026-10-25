# frozen_string_literal: true

require "icalendar"
require "icalendar/tzinfo"

module ScheduleConcern
  extend ActiveSupport::Concern

  included do
    # These pages offer the person's own history years (years_combined), which
    # reach back to 1995 -- below setup_year's 1998 default floor.
    self.year_floor = 1990
    before_action :ensure_person_for_schedule
    before_action :setup_year
    before_action :setup_slot, only: [:destroy]
  end

  def index
    @schedule_entries, @schedule_positions = Scheduling::Query.find_for_query(@person.id, @year, only_signups: true)
    @upcoming_entries, @past_entries = Scheduling::Query.partition_by_time(@schedule_entries, cutoff: :end_time)
    @overlapping_entries = @upcoming_entries.filter(&:is_overlapping)
  end

  def signups
    slot_id = params.expect!(:slot_id).to_i
    unless (slot = Slot.find(slot_id))
      flash[:error] = "No such slot"
      redirect_to schedule_redirect_path
      return
    end

    unless PersonPosition.have_position?(@person, slot.position_id)
      flash[:error] = "Position is not held."
      redirect_to schedule_redirect_path
      return
    end

    signups = Slot.retrieve_sign_ups(slot)
    render turbo_stream: turbo_stream.update("signups-#{slot.id}", partial: "people_signed_up", locals: { signups: })
  end

  def export
    entries, _ = Scheduling::Query.find_for_query(@person.id, @year, only_signups: true)

    cal = Icalendar::Calendar.new
    timezones = {}
    entries.each do |entry|
      slot = entry.slot

      # the icalendar gem does not have an interface to add timezones without
      # requiring a datetime. Stupid.
      unless timezones[slot.timezone]
        tz = TZInfo::Timezone.get slot.timezone
        cal.add_timezone tz.ical_timezone(slot.begins)
        timezones[slot.timezone] = true
      end

      cal.event do |e|
        e.uid = "clubhouse-#{slot.id}@burningman.org"
        e.dtstart = Icalendar::Values::DateTime.new slot.begins, "tzid" => slot.timezone
        e.dtend = Icalendar::Values::DateTime.new slot.ends, "tzid" => slot.timezone
        e.summary = entry.position.title
        e.description = "#{slot.description}\n#{slot.url}\n"
      end
    end

    send_data(
      cal.to_ical,
      filename: "#{Current.year}-ranger-calendar.ics",
      type: "text/calendar",
      disposition: "attachment"
    )
  end

  def destroy
    if @slot.has_started || @slot.has_ended
      redirect_to schedule_redirect_path(year: @year), error: "The shift cannot be removed because it has #{@slot.has_started ? "started" : "ended"}"
      return
    end

    result = Scheduling::Signup.remove(@person, @slot)
    if result.status == Scheduling::STATUS_SUCCESS
      redirect_to schedule_redirect_path(year: @year), success: "Shift removed."
      return
    end

    redirect_to schedule_redirect_path(year: @year), error: "The shift could not be removed. Reload the page and try again."
  end

  def signup_summary
    @summary = Scheduling::Summaries.schedule_summary_for_person_year(@person.id, @year)
  end

  private

  def ensure_person_for_schedule
    @person ||= current_user
  end

  def setup_slot
    slot_id = params.expect!(:slot_id).to_i
    unless PersonSlot.have_slot?(@person.id, slot_id)
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: [
            ui_toast_stream("You are not signed up for the shift", :error),
            modal_close_dialog
          ]
        }
        format.html {
          flash[:error] = "Shift does not exist."
          redirect_to schedule_redirect_path
        }
      end
      return false
    end

    unless (@slot = Slot.find(slot_id))
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: [
            ui_toast_stream("The shift does not exist", :error),
            modal_close_dialog
          ]
        }
        format.html {
          flash[:error] = "Shift does not exist."
          redirect_to schedule_redirect_path
        }
      end
      return false
    end

    @position = @slot.position
    true
  end
end
