# frozen_string_literal: true

# HQ-scoped twin of Person::SchedulingController — the schedule / sign-ups,
# hours & credits, and qualifications pages rendered inside the HQ Window
# Interface shell so the window operator never leaves /hq to look after a
# Ranger's shifts. Replaces the sidebar item that used to link out to
# /person/:id/schedule.
#
# HqConcern MUST be included first: inclusion order sets before_action order, so
# its set_person runs ahead of ScheduleConcern's ensure_person_for_schedule,
# whose `@person ||= current_user` then no-ops and leaves the SUBJECT person
# loaded rather than the operator. Person::SchedulingController orders
# PersonConcern the same way; reversing it would schedule shifts for the wrong
# human.
class Hq::SchedulingController < ApplicationController
  include HqConcern
  include QualificationsConcern
  include ScheduleConcern

  # The shell chrome is only needed by the actions that render the "hq" layout.
  # Skipping it elsewhere is not a micro-optimisation: load_hq_shell consumes
  # the once-per-person session[:hq_warned_person_id] flag, so letting it run on
  # the turbo-stream, download, and redirect actions would silently eat the
  # operator's entry-warning modal.
  skip_before_action :load_hq_shell, only: [:signups, :export, :destroy]

  before_action :set_back_to, only: [:qualifications]

  private

  def schedule_redirect_path(**options)
    hq_scheduling_path(@person, **options)
  end

  # Locked to the current year, deliberately ignoring params[:year]: the HQ
  # shell has no year selector (see HqConcern), and neither does the hero panel
  # on these pages. Overrides ApplicationController#setup_year.
  def setup_year
    @year = Current.year
    @is_current_year = true
  end

  # No year prefix on the label — unlike /person, the year here is fixed.
  def set_back_to
    @back_to_url = hq_scheduling_path(@person)
    @back_to_label = "Schedule & Sign-Ups"
    @signups_url = hq_scheduling_sign_ups_path(@person)
  end
end
