# frozen_string_literal: true

# The Alpha Schedule (upstream Ember mentor/schedule off
# MentorController::alphaSchedule -> Alpha::retrieveAlphaScheduleForYear).
# A year's Alpha shifts, then one shift at a time: its roster, its sign-ins,
# and the three sheets the mentor cadre runs Alpha day from.
#
# Deliberate departures from upstream, settled when this page was specced
# (see .scratch/mentoring-alpha-schedule/PLAN.md):
#
#   * Upstream stacked every shift into accordions on a single page. Each
#     shift owns a page here, so a roster is linkable and the three sheets
#     get real URLs instead of swapped-in components.
#   * Only Alpha and Prospective accounts may be added. Upstream says so in
#     the dialog but never enforces it; Mentoring::AlphaSchedule::RostersController
#     checks server-side and force does not bypass the check.
#   * Inactive shifts are listed (badged) rather than hidden -- a dormant
#     shift that still has sign-ups is what a mentor lead needs to catch.
class Mentoring::AlphaScheduleController < Mentoring::AlphaSchedule::BaseController
  before_action :load_slot, except: [:index]
  before_action :load_roster, only: [:show, :signup_sheet, :info_sheet, :apparel]

  # Info and Apparel describe who is signed in, so they are meaningless before
  # anyone is. The shift page's buttons open the "no Alphas" modal instead of
  # navigating; this guards the direct URL, which cannot raise a modal.
  before_action :require_signed_in_alphas, only: [:info_sheet, :apparel]

  # How many blank standby entries to print for walk-ups. A count of blanks,
  # not a pagination constant -- the sheets let CSS decide where pages break.
  STANDBY_ROWS = 14

  # Deliberately NO rows-per-page constants. Upstream slices the roster into
  # fixed pages and prints "Page N of M" from the slice index, which cannot
  # stay true: a block grows when someone's training description wraps, so a
  # fixed count either wastes a third of the paper or pushes blocks onto
  # unlabelled extra sheets (measured: 21 sign-ups at 7/page printed 7
  # physical sheets claiming "of 5"). Instead every block carries
  # `break-inside: avoid` and the browser paginates; the table header repeats
  # natively, so each sheet identifies itself. Where a sheet wants upstream's
  # page numbering it declares an @page margin box with counter(page) /
  # counter(pages) -- Chrome renders those, and they count the sheets that
  # actually came out of the printer.

  def index
    @shifts = AlphaShiftRoster.shifts_for_year(@year)
  end

  def show
  end

  # Upstream's "No Alphas Found" dialog, reached from the Info and Apparel
  # buttons while no one is signed in. A dialog cannot be raised by a plain
  # GET landing, so the buttons aim at this frame instead of the sheet.
  def no_alphas
    render layout: false
  end

  # Every sign-up gets a handwriting block, then blank standby pages for
  # walk-ups. The only sheet with no signed-in guard: it exists precisely to
  # collect the sign-ins.
  def signup_sheet
    @standby_rows = STANDBY_ROWS
    render layout: "print"
  end

  # Who is signed in, with the mentor history and notes a mentor needs in hand.
  def info_sheet
    render layout: "print"
  end

  # Shirts for the signed-in roster, split so a bonked Alpha's apparel is not
  # handed out with everyone else's, plus totals that exclude the bonks.
  def apparel
    bonked, passing = @roster.signed_in.partition(&:bonked?)

    # Both groups always print, empty or not: "no one bonked" and "a page went
    # missing" must not look the same on paper.
    @groups = [
      { title: "Pass/Pending", entries: passing },
      { title: "Bonked", entries: bonked }
    ]
    @shirt_totals = ShirtTotals.for_people(passing.map(&:person))
    render layout: "print"
  end

  private

  def load_roster
    @roster = AlphaShiftRoster.for_slot(@slot)
  end

  def require_signed_in_alphas
    return if @roster.any_signed_in?

    redirect_to mentoring_alpha_schedule_shift_path(@slot),
                error: "No Alphas are signed into this shift yet, so that sheet has nothing to print."
  end
end
