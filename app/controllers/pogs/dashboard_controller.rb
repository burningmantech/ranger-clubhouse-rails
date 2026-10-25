# frozen_string_literal: true

# Meal and shower pog statistics for one event year, counted by the day each
# pog was issued (person_pog.issued_at).
class Pogs::DashboardController < ApplicationController
  layout "pogs"

  # Not Event Management: it keeps Person › Pogs and the HQ window.
  authorize_role [Role::ADMIN, Role::POG_MANAGEMENT],
                 message: "Admin or Pog Management role required to view pog statistics."

  # Pog tracking began with the 2023 event.
  self.year_floor = 2023

  before_action :setup_year

  def index
    @report = PogStatsReport.execute(year: @year)
  end
end
