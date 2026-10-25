# frozen_string_literal: true

# The Alpha Acceptance Sheets (upstream Ember mentor/acceptance-sheets off
# MentorController::alphas -> Alpha::retrieveAllAlphas). Pick this year's
# Alphas, print one acceptance form each: the sheet the mentor cadre signs to
# accept an Alpha into the Rangers.
#
# Deliberate departures from upstream, settled when this page was specced
# (see .scratch/mentoring-alpha-acceptance-sheets/PLAN.md):
#
#   * Filtering and selection are server-side. Upstream filters the table in
#     the browser and swaps the print view in with a tracked flag; here the
#     filters are a GET form and printing is its own bookmarkable URL, so a
#     sheet can be re-printed from history without re-picking the roster.
#   * A second filter narrows to Alphas with or without issues (Mike,
#     2026-08-04). Upstream offers the shift filter only, leaving the Errors
#     column as the sole way to spot who is not ready.
#   * An empty selection redirects with a message instead of raising the
#     browser dialog upstream shows -- a GET landing cannot raise a modal.
class Mentoring::AlphaAcceptanceSheetsController < ApplicationController
  layout "mentoring"

  before_action :setup_year

  # Upstream Gate isMentor.
  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to print Alpha acceptance sheets."

  # The shared "no filter" sentinel, so chips and URLs drop it the way every
  # other filtered page does. The page's own filter values live on
  # AlphaAcceptanceSheets, which the view helper reads too.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  def index
    @roster = AlphaAcceptanceSheets.for_year(@year)
    @filter_params = filter_params
    @entries = apply_filters(@roster)

    # Counted over the whole roster, not the filtered rows: the stat boxes
    # describe this year's Alphas, while the count line describes what is on
    # screen. Filtered totals would read as "only 3 Alphas exist".
    @total = @roster.size
    @issue_count = @roster.count(&:issues?)
    @alpha_slots = alpha_slots
  end

  # One acceptance form per selected Alpha, page-break separated. Ids arrive
  # from the picker's checkboxes; the roster lookup drops anything that is not
  # a current Alpha, so a hand-edited URL cannot print an arbitrary person.
  def print_sheets
    ids = IdList.parse(params.permit(person_ids: [])[:person_ids])
    @entries = ids.any? ? AlphaAcceptanceSheets.for_year(@year, person_ids: ids) : []

    if @entries.empty?
      redirect_to(mentoring_alpha_acceptance_sheets_path(filter_params),
                  error: "Pick at least one Alpha to print an acceptance form for.")
      return
    end

    @back_params = filter_params
    render layout: "print"
  end

  private

  # Pinned, not read from params: the roster is who is an Alpha right now, so
  # honouring ?year= would list today's Alphas against a past year's shifts and
  # training. Matches the three other current-standing Mentoring pages.
  def setup_year
    @year = Current.year
  end

  def filter_params
    {
      shift: params[:shift].presence || ALL_FILTER,
      issues: params[:issues].presence || ALL_FILTER
    }
  end

  # The year's Alpha shifts for the filter dropdown, earliest first. Inactive
  # shifts are listed for the same reason the Alpha Schedule lists them: a
  # dormant shift that still has sign-ups is exactly what wants noticing.
  def alpha_slots
    Slot.for_year(@year).for_position(Position::ALPHA).ordered_by_begins.to_a
  end

  def apply_filters(entries)
    entries = filter_by_shift(entries, @filter_params[:shift])
    filter_by_issues(entries, @filter_params[:issues])
  end

  def filter_by_shift(entries, shift)
    case shift
    when ALL_FILTER then entries
    when AlphaAcceptanceSheets::NO_SHIFT then entries.select { |entry| entry.alpha_slots.empty? }
    else
      slot_id = shift.to_i
      entries.select { |entry| entry.alpha_slots.any? { |slot| slot.id == slot_id } }
    end
  end

  def filter_by_issues(entries, issues)
    case issues
    when AlphaAcceptanceSheets::WITH_ISSUES then entries.select(&:issues?)
    when AlphaAcceptanceSheets::WITHOUT_ISSUES then entries.reject(&:issues?)
    else entries
    end
  end
end
