# frozen_string_literal: true

# Everyone who might become an Alpha this year, for the Mentors (Ember
# mentor/potentials, which rendered the same <UnifiedFlagging> component as the
# /vc and In-Person Training pipeline pages off MentorController::mentees).
#
# Two deliberate departures from upstream, both settled when this page was
# specced (see .scratch/mentoring-potential-alphas/PLAN.md):
#
#   * The roster is current standing -- every Person whose status is Prospective
#     or Alpha right now -- rather than upstream's status-audit roster narrowed
#     to people already signed up for training (`have_training=1`). Someone who
#     has not booked a training session yet is exactly who a mentor needs to
#     chase, so they belong on the page; the Training filter recovers upstream's
#     narrower view. This is also why the page has no year selector: current
#     status cannot describe a past year, and upstream's in-year bonk exclusions
#     are moot here because a bonked person is no longer a Prospective.
#   * Gender is not shown on rows (upstream's @showGender), so rows stay
#     identical to the other two pipeline pages.
#
# The cohort split is this page's own: Prospectives are the people to triage,
# Alphas have already been accepted and are watched rather than judged.
class Mentoring::PotentialAlphasController < ApplicationController
  include UnifiedFlaggingConcern

  layout "mentoring"

  before_action :setup_year

  # Upstream Gate isMentor.
  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to view potential Alphas."

  # Cohort first, then the severity groups within each. group_by preserves
  # Intake's ordering, so both levels arrive already sorted.
  def index
    shown = unified_flagging_index_summaries
    review_selection(shown)
    return render_review_pane if review_pane_request?

    @cohorts = shown.group_by { |summary| cohort_of(summary) }
                    .transform_values { |rows| rows.group_by { |summary| summary[:group] } }
    # Counted before filtering: the stat boxes describe the roster ("114
    # Prospectives"), while each section's badge counts the rows it is showing.
    # Filtered totals in the stat boxes would read as "no one holds this status".
    roster = unified_flagging_summaries
    cohorts = Mentoring::PotentialAlphasHelper::COHORTS.keys
    @cohort_totals = cohorts.index_with { |c| roster.count { cohort_of(_1) == c } }
    @cohort_issue_totals = cohorts.index_with { |c| roster.count { cohort_of(_1) == c && has_issue?(_1) } }
    @personnel_flag_count = roster.count { |summary| summary[:personnel_issue] }
  end

  private

  # Pinned, not read from params: the roster is current standing, so honouring
  # ?year= would clip the ranks and notes to a past year while still listing
  # today's Prospectives.
  def setup_year
    @year = Current.year
  end

  # Memoized because #index reads it twice -- once through the concern, which
  # filters it, and once directly for the unfiltered roster figures.
  def unified_flagging_summaries
    @unified_flagging_summaries ||= Intake.retrieve_current_potentials(@year)
  end

  def cohort_of(summary)
    summary[:person].status == Person::ALPHA ? :alpha : :prospective
  end

  # The same partition the with-issues sections use, so a stat box and the
  # section it summarizes always report the same number. Deliberately the
  # display group rather than summary[:flagged]: that one is true for anyone
  # marked in ANY year, while the sections split on where a person stands now.
  def has_issue?(summary)
    Mentoring::PotentialAlphasHelper::ISSUE_GROUPS.include?(summary[:group])
  end

  # The extra dimension upstream carried as six independent checkboxes
  # (Untrained / RRN / VC / Training / Mentor / Personnel flagged). One select
  # instead: the combinations only ever narrowed toward an empty list, and
  # "Untrained" is what the Training filter already does.
  def unified_flagging_filter_params
    super.merge(flagged: params[:flagged].presence || ALL_FILTER)
  end

  def apply_unified_flagging_filters(summaries)
    flagged = @filter_params[:flagged]
    return super if flagged == ALL_FILTER

    super.select { |summary| flagged_by?(summary, flagged) }
  end

  # Matches on what the row actually displays -- the latest rank per team --
  # rather than upstream's "any year, ever". A rank the row lists on its gray
  # line is the rank the filter selects on; older ranks are one row-expansion away.
  def flagged_by?(summary, flagged)
    case flagged
    when "personnel" then summary[:personnel_issue]
    when "bonk" then summary[:bonk].present?
    else summary[:ranks].any? { |entry| entry[:team] == flagged && entry[:rank] >= Intake::BELOW_AVERAGE }
    end
  end

  # The shared partials pass the page year (@year, pinned above, scopes the
  # ranks and notes); this page has no year in its URLs, so both builders drop
  # it rather than trailing a meaningless ?year= through every line link.
  def unified_flagging_path(**params)
    mentoring_potential_alphas_path(**params.except(:year))
  end

  def unified_flagging_detail_path(person, **_params)
    mentoring_potential_alphas_detail_path(person)
  end

  # Writable, like upstream: filing a mentor note is the point of the page.
  # Which teams a viewer may actually write for is decided by
  # Person::IntakeNotesController::PERMISSION_ROLE_FOR_TYPE, so a Mentor gets
  # the Mentor team only -- upstream's @mentorNotesOnly, reached through the
  # role map instead of a flag. An Admin keeps all four teams here, which
  # upstream's flag would have withheld; they can write them from the person
  # page regardless, so hiding the buttons would only add a detour.
  def unified_flagging_read_only?
    false
  end

  def unified_flagging_origin
    { origin: "mentoring" }
  end
end
