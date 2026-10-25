# frozen_string_literal: true

# Alpha Pod Management (upstream Ember mentor/pod off PodController).
#
# An Alpha Mentor Walk goes out in pods: a few mentors, a MITten or two, and
# the Alphas they walk. This page forms them on the day -- pick the shift,
# create as many pods as the walk needs, and drop each person who has checked
# in into one.
#
# Deliberate departures from upstream, settled when this page was specced
# (see .scratch/mentoring-alpha-pods/PLAN.md):
#
#   * Pods are cards in a responsive grid rather than columns of a wide
#     table. Pods are formed on playa on a phone; upstream's six-column
#     layout needs a laptop. The column form survives as the print sheet,
#     which is the shape that actually belongs on paper.
#   * Only active Alpha shifts are listed. Upstream's page says as much and
#     then filters nothing.
#   * Pod ordering is renumbered server-side in one transaction; upstream
#     does it in the browser and loses track of itself halfway through.
class Mentoring::AlphaPodsController < Mentoring::AlphaPods::BaseController
  before_action :load_slot, except: [:index]
  before_action :load_board, only: [:show, :print_sheet]

  def index
    @shifts, @pod_counts = AlphaPodBoard.shifts_for_year(@year)
  end

  def show
  end

  # The walk order on paper: one column per pod, six to a page, landscape.
  # This is upstream's on-screen layout, kept for the one job it is best at.
  def print_sheet
    render layout: "print"
  end

  private

  def load_board
    @board = AlphaPodBoard.for_slot(@slot)
  end
end
