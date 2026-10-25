# frozen_string_literal: true

# Shared gate and slot lookup for the Alpha Schedule pages and their roster
# writes. Upstream Gate isMentor covers the whole mentor/schedule surface,
# reads and writes alike.
class Mentoring::AlphaSchedule::BaseController < ApplicationController
  layout "mentoring"

  before_action :setup_year

  # `load_slot` is registered by each subclass, not here: Rails raises when an
  # `except:` list names an action the controller does not define, and only
  # the page controller has the slotless index to exclude.

  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to view the Alpha schedule."

  # The year selector's floor, matching upstream's YearSelect minYear.
  self.year_floor = 2008

  private

  # Looked up across every year and including inactive shifts on purpose: a
  # shift page belongs to its own year, so a bookmarked link keeps meaning the
  # same shift whatever the selector last showed. Restricted to the Alpha
  # position -- these pages cannot manage any other kind of shift.
  def load_slot
    @slot = Slot.for_position(Position::ALPHA).find_by(id: params[:slot_id])
    return if @slot

    redirect_to mentoring_alpha_schedule_path(year: @year),
                error: "That shift is not an Alpha shift. Pick a shift from the schedule."
  end
end
