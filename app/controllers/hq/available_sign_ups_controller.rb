# frozen_string_literal: true

# Available Sign-Ups browser for the HQ Window Interface
# (/hq/:person_id/schedule/sign-ups), the HQ-scoped twin of
# Person::AvailableSignUpsController.
#
# The pages themselves live in app/views/common/available_sign_ups/* and are
# namespace-agnostic; the wrappers under app/views/hq/available_sign_ups/ only
# supply the /hq path builders so the window operator never leaves the HQ shell.
class Hq::AvailableSignUpsController < ApplicationController
  # HqConcern MUST be included first. Inclusion order is before_action order,
  # so its set_person runs ahead of AvailableSignUpsConcern's
  # ensure_person_for_available_sign_ups, whose `@person ||= current_user` then
  # no-ops and leaves the SUBJECT person loaded rather than the operator.
  # Reversing these would silently sign up the wrong human.
  include HqConcern
  include AvailableSignUpsConcern

  # create/destroy answer with a turbo_stream and never render the HQ shell.
  # Skipping is not an optimisation: load_hq_shell consumes the once-per-person
  # session[:hq_warned_person_id] flag, so running it here would eat the
  # operator's entry-warning modal before the shell ever got to show it.
  skip_before_action :load_hq_shell, only: [:create, :destroy]

  private

  # The HQ shell has no year selector (see HqConcern), so HQ scheduling is
  # locked to the current year and deliberately ignores params[:year].
  def setup_year
    @year = Current.year
    @is_current_year = true
  end

  def schedule_redirect_path(**options)
    hq_scheduling_path(@person, **options)
  end

  def sign_ups_redirect_path(**options)
    hq_scheduling_sign_ups_path(@person, **options)
  end

  def sign_ups_position_redirect_path(position_id)
    hq_scheduling_sign_ups_position_path(@person, position_id)
  end
end
