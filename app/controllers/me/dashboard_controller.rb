# frozen_string_literal: true

class Me::DashboardController < ApplicationController
  layout "me"

  # Past prospectives keep their dashboard (ApplicationController#confine_past_prospective).
  skip_before_action :confine_past_prospective

  helper_method :service_info
  def index
    @person = current_user
    @milestones = Milestones.build_for_person(@person)
    @dashboard = Dashboard.new(DashboardFacts.from_milestones(@milestones, @person))
    @motds = Motd.retrieve_announcements_for_person(@person.id, @person.status)
    # /me?tour=1 runs the first-sign-in tour again without recording it, for
    # someone it has recorded; for anyone else the run records, as on /me.
    @replay_tour = params[:tour].present? && current_user.on_boarded_at.present?
  end

  # The first-sign-in tour (me/dashboard/_onboarding) reports that it ran,
  # however it ended. update_column on purpose: Person is audit_model, and a
  # tour timestamp is self-service bookkeeping like last_seen_at, not an
  # audit event; nor may an older row's validations stand in the way.
  def onboarded
    current_user.update_column(:on_boarded_at, Current.time)
    head :no_content
  end

  private

  def service_info
    person = current_user
    ranger_years = person.years_as_ranger.length
    echelon_years = person.years_as_contributor.length

    return "stopping by" if ranger_years.zero? && echelon_years.zero?

    info = []
    info << "rangering #{pluralize(ranger_years, 'burn')}" if ranger_years.positive?
    info << "volunteering #{pluralize(echelon_years, 'year')}" if echelon_years.positive?

    info.join(" and for ")
  end
end
