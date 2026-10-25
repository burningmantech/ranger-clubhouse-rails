# frozen_string_literal: true

# The mentor cadre's end-of-season review of a year's Prospective and Alpha
# class (Ember mentor/post-season-summary off MentorController::mentees).
# Who signed up for an Alpha shift, who actually walked one, who bonked, who
# carries a mentor rank of 3 or 4, and what the Mentors wrote about them.
#
# Deliberate departures from upstream, all settled when this page was specced
# (see .scratch/mentoring-post-season-summary/PLAN.md):
#
#   * Mentor notes live in the shared collapsed detail frame rather than being
#     rendered open on every row. That frame already carries the note controls,
#     so upstream's writability survives unchanged, and a 200-row class no
#     longer loads 200 note streams up front.
#   * Upstream's separate rank-3/4 chip is not ported: the shared row's gray
#     line already lists the mentor team's rank with its year ("Mentor 3/Yellow
#     (2025)"), so a second chip would say it twice. The
#     viewed-year mentor rank is still computed -- it is what splits the two
#     sections and what the Rank filter selects on.
#   * The mentor filter is single-select. Upstream's multi-select would need
#     array params and an N-value chip model that filter_bar does not have,
#     to serve a combination no one asks for.
#   * Upstream's shipped chip colors give "no signup" and "signed up, didn't
#     walk" the same warning color, so the two states look identical; its own
#     spec says the first should be red. Fixed here -- see #post_season_signup
#     in the helper.
class Mentoring::PostSeasonSummaryController < ApplicationController
  include UnifiedFlaggingConcern

  layout "mentoring"

  before_action :setup_year

  # Upstream Gate isMentor.
  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to view the post season summary."

  # The year selector's floor, matching upstream's YearSelect minYear.
  self.year_floor = 2008

  def index
    shown = unified_flagging_index_summaries
    review_selection(shown)
    return render_review_pane(**Mentoring::PostSeasonSummaryHelper::PANE_EXTRAS) if review_pane_request?

    @sections = shown.group_by { |summary| section_of(summary) }

    # Counted before filtering: a stat box describes the class, while each
    # section's badge counts the rows it is showing. Filtered stat boxes would
    # read as "no one walked a shift", which is a different claim.
    roster = unified_flagging_summaries
    @mentee_count = roster.size
    @walked_count = roster.count { |summary| walked?(summary) }
    @flagged_count = roster.count { |summary| section_of(summary) == :flagged }
    @no_signup_count = roster.count { |summary| signup_state(summary) == :none }

    # Built from the unfiltered roster so picking a mentor never shrinks the
    # list of mentors you can pick from. One canonical id => callsign hash,
    # callsign-ordered; the select and the filter chips both read it, so
    # neither can disagree with the other about which callsign an id names.
    @mentor_labels = mentor_labels(roster)
  end

  private

  # Memoized because #index reads it twice -- once through the concern, which
  # filters it, and once directly for the unfiltered figures.
  def unified_flagging_summaries
    @unified_flagging_summaries ||= Intake.retrieve_post_season_class(@year)
  end

  # Upstream's Section A: a bonk of either kind, an uberbonk, or a mentor rank
  # of 3 or 4 in the viewed year. Everyone else is Section B.
  #
  # Deliberately NOT Intake's severity groups, which the sibling pages split on:
  # those fold in every team's ranks, and the question this page asks is what
  # the MENTORS concluded.
  def section_of(summary)
    # summary[:bonk] is the viewed year's bonk on this page (Intake re-points
    # it in retrieve_post_season_class), so the section split and the chip on
    # the row read the same fact.
    bonked = summary[:bonk].present?
    uberbonked = summary[:person].status == Person::UBERBONKED

    bonked || uberbonked || summary[:mentor_rank] >= Intake::BELOW_AVERAGE ? :flagged : :other
  end

  # Asked of the helper rather than re-derived, so the Walked stat box, the
  # Sign-up filter and the chip on the row can never disagree about who walked.
  def walked?(summary)
    signup_state(summary) == :walked
  end

  # The helper's state, mentors first: a recorded walk counts as signed up and
  # walked even when its sign-up row has since gone, so a walk-up is never
  # listed under "No Alpha sign-up" beside the "Walked a shift" on its line.
  def signup_state(summary)
    helpers.post_season_signup_state(summary)
  end

  def mentor_labels(roster)
    roster.flat_map { |summary| summary[:mentors] }
          .uniq { |mentor| mentor[:id] }
          .sort_by { |mentor| mentor[:callsign].to_s.downcase }
          .to_h { |mentor| [mentor[:id].to_s, mentor[:callsign]] }
  end

  # No Training filter: whether someone made it to training is a pre-season
  # question, and this is the post-season page. The concern neither reads nor
  # applies ?training= when this answers false.
  def unified_flagging_training_filter?
    false
  end

  # Derived from FACETS.keys so a facet can never be offered but not read --
  # the keys, the selects, and #facet_matches? all iterate the same registry.
  def unified_flagging_filter_params
    super.merge(Mentoring::PostSeasonSummaryHelper::FACETS.keys.index_with { |facet| facet_param(facet) })
  end

  # Only values the select actually offers are accepted; anything else --
  # a typo, a stale bookmark, an array-shaped ?rank[]= param -- reads as the
  # inactive sentinel instead of silently narrowing the roster (or, for
  # :rank's to_i, crashing on a non-String). :mentor is the one facet whose
  # values are data rather than a fixed set; a garbage mentor id simply
  # matches no one, which the empty state makes visible.
  def facet_param(facet)
    value = params[facet]
    return ALL_FILTER unless value.is_a?(String) && value.present?
    return value if facet == :mentor

    Mentoring::PostSeasonSummaryHelper::FACETS.dig(facet, :values).key?(value) ? value : ALL_FILTER
  end

  # Each facet AND-narrows, which is the single-select shape upstream itself
  # landed on after its checkbox version crowded the bar -- so its
  # OR-within-a-facet rule is moot and not ported.
  def apply_unified_flagging_filters(summaries)
    super.select { |summary| Mentoring::PostSeasonSummaryHelper::FACETS.all? { |facet, _| facet_matches?(summary, facet) } }
  end

  def facet_matches?(summary, facet)
    value = @filter_params[facet]
    return true if value == ALL_FILTER

    case facet
    when :section then section_of(summary).to_s == value
    when :signup then signup_matches?(summary, value)
    when :outcome then outcome_matches?(summary, value)
    when :rank then value == "none" ? summary[:mentor_rank].zero? : summary[:mentor_rank] == value.to_i
    when :notes then value == "any" ? summary[:mentor_notes] : !summary[:mentor_notes]
    when :mentor then summary[:mentors].any? { |mentor| mentor[:id].to_s == value }
    end
  end

  def signup_matches?(summary, value)
    case value
    when "none" then signup_state(summary) == :none
    when "signed-up" then signup_state(summary) != :none
    else walked?(summary)
    end
  end

  # Uber-bonk is the account status, not a mentor verdict -- upstream reads it
  # off person.status for exactly this reason.
  def outcome_matches?(summary, value)
    return summary[:person].status == Person::UBERBONKED if value == "uber-bonk"

    summary[:mentor_status] == value
  end

  def unified_flagging_path(**params)
    mentoring_post_season_summary_path(**params)
  end

  # Unlike the sibling mentoring pages, the year is kept: this page has a year
  # selector, so a detail frame must be fetched for the year on screen.
  def unified_flagging_detail_path(person, **params)
    mentoring_post_season_summary_detail_path(person, **params)
  end

  # Writable, like upstream: recording what the Mentors concluded is the point
  # of the review. Which teams a viewer may actually write for is decided by
  # Person::IntakeNotesController::PERMISSION_ROLE_FOR_TYPE, so a Mentor gets
  # the Mentor team only.
  def unified_flagging_read_only?
    false
  end

  # Its own token, not the sibling pages' "mentoring": that one returns to
  # /mentoring/potential-alphas, a current-standing roster that cannot hold a
  # past year's bonked mentee, so filing a note here would strand the reader on
  # a page their row is absent from. `origin_year` carries the season back, as
  # the /vc copy does -- the two /mentoring siblings have no year to carry.
  def unified_flagging_origin
    { origin: "mentoring_post_season", origin_year: @year }
  end
end
