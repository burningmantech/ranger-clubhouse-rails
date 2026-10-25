# frozen_string_literal: true

# Where this year's Prospective and Alpha class stands, for the Mentors
# (Ember mentor/alpha-status off MentorController::mentees with exclude_bonks).
# Read-only: this page reports, and the two sibling /mentoring pages are where
# a mentor writes.
#
# Three deliberate departures from upstream, all settled when this page was
# specced (see .scratch/mentoring-alpha-status/PLAN.md):
#
#   * Sections are keyed to the next action -- Resolve first / Ready for Alpha
#     status / Became an Alpha / Waiting on training -- rather than to upstream's
#     severity split. That is what lets the Trained? and Is Alpha? checkmark
#     columns go: the section a person sits in already answers both, and a pair
#     of booleans is a poor way to ask "who do I chase today?".
#   * "Resolve first" uses Intake's severity groups, so a rank 3/4 from ANY
#     intake team lands there. Upstream checks mentor ranks alone
#     (have_mentor_flags), which would put a VC rank 4 in with the clean rows on
#     the one page whose purpose is deciding whether to convert them. It also keeps
#     all four pipeline pages partitioning people identically.
#   * Upstream's two summary figures are not ported as written: statusEligibleCount
#     counts `is_trained`, a field the API never sets, so upstream's "Status
#     eligible" is always 0; and positionEligibleCount is printed by the template
#     but never defined. The first is computed correctly here as the "Ready for
#     Alpha status" count; the second is dropped -- the current API build has no
#     field to derive it from.
class Mentoring::AlphaStatusController < ApplicationController
  include UnifiedFlaggingConcern

  layout "mentoring"

  before_action :setup_year

  # Upstream Gate isMentor.
  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to view Alpha status."

  def index
    shown = unified_flagging_index_summaries
    review_selection(shown)
    return render_review_pane if review_pane_request?

    @sections = shown.group_by { |summary| section_of(summary) }
    # Counted before filtering: the stat boxes describe the class, while each
    # section's badge counts the rows it is showing. Filtered stat boxes would
    # read as "no one has become an Alpha", which is a different claim.
    roster = unified_flagging_summaries
    @section_totals = roster.group_by { |summary| section_of(summary) }.transform_values(&:size)
    @personnel_flag_count = roster.count { |summary| summary[:personnel_issue] }
  end

  private

  # Pinned, not read from params. The roster IS year-based, but the page offers
  # no year selector, so honouring a stray ?year= would clip every row's ranks
  # and notes to a year the reader never chose.
  def setup_year
    @year = Current.year
  end

  # Memoized because #index reads it twice -- once through the concern, which
  # filters it, and once directly for the unfiltered figures.
  def unified_flagging_summaries
    @unified_flagging_summaries ||= Intake.retrieve_year_class(@year)
  end

  def became_alpha_ids
    @became_alpha_ids ||= Intake.became_alpha_ids(@year)
  end

  # First match wins, which is what keeps anyone from appearing twice. The
  # order is the order of the sections on the page, and each rule is the
  # section's own definition:
  #
  #   * a raised concern outranks everything -- it is what has to happen first
  #   * then "has already been an Alpha", read from the audit trail so a Shiny
  #     Penny is not offered up for conversion a second time
  #   * then trained-and-still-a-Prospective, which is the convertible set
  #   * everyone left is waiting on training
  def section_of(summary)
    return :resolve if Mentoring::AlphaStatusHelper::ISSUE_GROUPS.include?(summary[:group])
    return :alpha if became_alpha_ids.include?(summary[:person].id) || summary[:person].status == Person::ALPHA
    return :ready if summary[:training_status] == "trained"

    :waiting
  end

  # The same "Flagged by" select the sibling page carries. Upstream's other two
  # filter options, "Status eligible" and "Alpha status", are not filters here:
  # they are sections 2 and 3, which is the point of the layout.
  def unified_flagging_filter_params
    super.merge(flagged: params[:flagged].presence || ALL_FILTER)
  end

  def apply_unified_flagging_filters(summaries)
    flagged = @filter_params[:flagged]
    return super if flagged == ALL_FILTER

    super.select { |summary| flagged_by?(summary, flagged) }
  end

  # Matches on what the row actually displays -- the latest rank per team --
  # rather than upstream's "any year, ever". Same rule as
  # /mentoring/potential-alphas, so the two pages answer a filter alike.
  def flagged_by?(summary, flagged)
    case flagged
    when "personnel" then summary[:personnel_issue]
    when "bonk" then summary[:bonk].present?
    else summary[:ranks].any? { |entry| entry[:team] == flagged && entry[:rank] >= Intake::BELOW_AVERAGE }
    end
  end

  # The shared partials pass the page year (@year, pinned above, is the class
  # year); this page has no year in its URLs, so both builders drop it rather
  # than trailing a meaningless ?year= through every line link.
  def unified_flagging_path(**params)
    mentoring_alpha_status_path(**params.except(:year))
  end

  def unified_flagging_detail_path(person, **_params)
    mentoring_alpha_status_detail_path(person)
  end

  # A status board. Filing a mentor note belongs on the two pages that already
  # take one, and Person::IntakeNotesController re-checks server-side anyway.
  def unified_flagging_read_only?
    true
  end

  def unified_flagging_origin
    {}
  end
end
