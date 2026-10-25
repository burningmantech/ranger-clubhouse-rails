# frozen_string_literal: true

# Shared plumbing for pages that show a person's on-playa volunteer history:
# total hours by position and by year (sourced from WorkHistoryReport), plus
# the three drill-down breakdown pages (one position/year cell, all of a
# position's years, an entire year) rendered from app/views/common/work_history.
#
# Including controllers must set @person (via PersonConcern, current_user, or
# otherwise) before this concern's before_action runs, declare their own
# authorization, and route position_summary/position_all/entire_year — this
# concern is deliberately authorization-agnostic since it backs both the
# self-service /me work-history page (any signed-in ranger) and the
# staff-facing /person/:id/work-history page (role-gated, arbitrary person).
module WorkHistoryConcern
  extend ActiveSupport::Concern

  included do
    before_action :load_work_history
  end

  def position_summary
    position_id, year = params.expect!(:position_id, :year)
    @year = year.to_i
    unless (@position = @history.positions.find { |p| p.id == position_id.to_i })
      return head :unprocessable_entity
    end

    unless (@entries = @position.years[@year]&.entries)
      return head :unprocessable_entity
    end

    render "common/work_history/position_summary"
  end

  def position_all
    position_id = params.expect!(:position_id).to_i
    unless (@position = @history.positions.find { |p| p.id == position_id })
      return head :unprocessable_entity
    end

    render "common/work_history/position_all"
  end

  def entire_year
    @year = params.expect!(:year).to_i
    unless (@entries = @history.year_totals[@year]&.entries)
      return head :unprocessable_entity
    end

    render "common/work_history/entire_year"
  end

  private

  def load_work_history
    @history = WorkHistoryReport.execute(@person.id)
  end
end
