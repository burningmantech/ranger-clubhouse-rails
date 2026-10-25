# frozen_string_literal: true

# Who signed up but never rangered the shift, and who rangered a shift they
# never signed up for, for a whole year. The positions index drills down into
# one position's shifts, mirroring the slots admin pages.
class Scheduling::FlakeReportController < ApplicationController
  include PositionLookupConcern

  layout "scheduling"

  # Upstream SlotPolicy: the before hook admits Admin and Edit Slots, and
  # report() admits Event Management.
  authorize_role [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT],
                 message: "Admin, Edit Slots, or Event Management role required " \
                          "to view the flake report."

  # The year selector's own floor -- the views read it back through the
  # `year_floor` helper, so a year the URL is allowed to ask for is always a
  # year the selector can show. Left at the 1998 default, ?year=2005 rendered a
  # page titled 2005 whose selector read the current year, and picking that
  # year fired no change event, so the reader could not get back.
  self.year_floor = 2008

  before_action :setup_year
  before_action :set_position, only: :position

  def index
    @summary = FlakeReport.summary(year: @year)
  end

  def position
    @detail = FlakeReport.position(year: @year, position: @position)
  end

  private

  def position_not_found_path
    scheduling_flake_report_path(year: @year)
  end
end
