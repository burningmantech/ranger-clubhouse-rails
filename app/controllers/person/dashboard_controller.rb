# frozen_string_literal: true

# Read-only administrative view of the Clubhouse dashboard as the person
# currently sees it — the same Milestones/DashboardFacts/Dashboard build as
# Me::DashboardController, minus the person's announcements.
class Person::DashboardController < ApplicationController
  layout "person"

  include PersonConcern

  def show
    @milestones = Milestones.build_for_person(@person)
    @dashboard = Dashboard.new(DashboardFacts.from_milestones(@milestones, @person))
  end
end
